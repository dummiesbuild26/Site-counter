import Foundation

// MARK: - Models

enum StatsRange: String, CaseIterable, Identifiable {
    case day = "24 Hours"
    case week = "7 Days"
    case month = "30 Days"

    var id: String { rawValue }
    var isHourly: Bool { self == .day }
}

struct StatPoint: Identifiable {
    let date: Date
    let requests: Int
    let pageViews: Int
    let uniques: Int
    let bytes: Int
    let cachedBytes: Int
    let cachedRequests: Int
    let threats: Int

    var id: Date { date }
}

struct CountryStat: Identifiable {
    let code: String
    let requests: Int

    var id: String { code }

    var name: String {
        Locale.current.localizedString(forRegionCode: code) ?? code
    }

    var flag: String {
        guard code.count == 2 else { return "🌐" }
        let scalars = code.uppercased().unicodeScalars.compactMap { UnicodeScalar(127397 + $0.value) }
        return String(String.UnicodeScalarView(scalars))
    }
}

struct ZoneInfo {
    let name: String
    let status: String
    let plan: String?
}

struct CloudflareError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

// MARK: - Client

/// Talks to the Cloudflare REST API (zone/account details) and the
/// GraphQL Analytics API (traffic stats).
struct CloudflareClient {
    let token: String

    private let baseURL = URL(string: "https://api.cloudflare.com/client/v4")!

    // MARK: REST

    func zoneInfo(zoneID: String) async throws -> ZoneInfo {
        struct Result: Decodable {
            struct Plan: Decodable { let name: String }
            let name: String
            let status: String
            let plan: Plan?
        }
        let result: Result = try await get("zones/\(zoneID)")
        return ZoneInfo(name: result.name, status: result.status, plan: result.plan?.name)
    }

    func accountName(accountID: String) async throws -> String {
        struct Result: Decodable { let name: String }
        let result: Result = try await get("accounts/\(accountID)")
        return result.name
    }

    private func get<T: Decodable>(_ path: String) async throws -> T {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let envelope = try? JSONDecoder().decode(RESTEnvelope<T>.self, from: data) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw CloudflareError(message: "Unexpected response from Cloudflare (HTTP \(status)).")
        }
        guard envelope.success, let result = envelope.result else {
            let message = envelope.errors?.map(\.message).joined(separator: "\n") ?? "Unknown error"
            throw CloudflareError(message: message)
        }
        return result
    }

    // MARK: GraphQL analytics

    func stats(zoneID: String, range: StatsRange) async throws -> (points: [StatPoint], countries: [CountryStat]) {
        let fields = """
            sum {
              requests
              pageViews
              bytes
              cachedBytes
              cachedRequests
              threats
              countryMap { clientCountryName requests }
            }
            uniq { uniques }
        """

        let query: String
        let variables: [String: String]
        let now = Date()

        if range.isHourly {
            query = """
            query ($zoneTag: string, $since: Time, $until: Time) {
              viewer {
                zones(filter: { zoneTag: $zoneTag }) {
                  groups: httpRequests1hGroups(
                    limit: 100
                    filter: { datetime_geq: $since, datetime_lt: $until }
                    orderBy: [datetime_ASC]
                  ) {
                    dimensions { datetime }
                    \(fields)
                  }
                }
              }
            }
            """
            let since = Calendar.utc.dateInterval(of: .hour, for: now.addingTimeInterval(-23 * 3600))!.start
            variables = [
                "zoneTag": zoneID,
                "since": Formatters.iso8601.string(from: since),
                "until": Formatters.iso8601.string(from: now),
            ]
        } else {
            query = """
            query ($zoneTag: string, $since: Date, $until: Date) {
              viewer {
                zones(filter: { zoneTag: $zoneTag }) {
                  groups: httpRequests1dGroups(
                    limit: 100
                    filter: { date_geq: $since, date_leq: $until }
                    orderBy: [date_ASC]
                  ) {
                    dimensions { date }
                    \(fields)
                  }
                }
              }
            }
            """
            let days = range == .week ? 6 : 29
            let since = Calendar.utc.date(byAdding: .day, value: -days, to: now)!
            variables = [
                "zoneTag": zoneID,
                "since": Formatters.day.string(from: since),
                "until": Formatters.day.string(from: now),
            ]
        }

        var request = URLRequest(url: baseURL.appendingPathComponent("graphql"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["query": query, "variables": variables])

        let (data, response) = try await URLSession.shared.data(for: request)
        let decoded: GraphQLResponse
        do {
            decoded = try JSONDecoder().decode(GraphQLResponse.self, from: data)
        } catch {
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw CloudflareError(message: "Could not read analytics response (HTTP \(status)).")
        }

        if let errors = decoded.errors, !errors.isEmpty {
            throw CloudflareError(message: errors.map(\.message).joined(separator: "\n"))
        }
        guard let zone = decoded.data?.viewer.zones.first else {
            throw CloudflareError(message: "No analytics found for this zone. Check the Zone ID and that the token has Analytics Read access.")
        }

        var countryTotals: [String: Int] = [:]
        let points: [StatPoint] = zone.groups.compactMap { group in
            let date: Date?
            if let datetime = group.dimensions.datetime {
                date = Formatters.iso8601.date(from: datetime)
            } else if let day = group.dimensions.date {
                date = Formatters.day.date(from: day)
            } else {
                date = nil
            }
            guard let date else { return nil }

            for entry in group.sum.countryMap ?? [] {
                countryTotals[entry.clientCountryName, default: 0] += entry.requests
            }
            return StatPoint(
                date: date,
                requests: group.sum.requests,
                pageViews: group.sum.pageViews,
                uniques: group.uniq.uniques,
                bytes: group.sum.bytes,
                cachedBytes: group.sum.cachedBytes,
                cachedRequests: group.sum.cachedRequests,
                threats: group.sum.threats
            )
        }

        let countries = countryTotals
            .map { CountryStat(code: $0.key, requests: $0.value) }
            .sorted { $0.requests > $1.requests }
        return (points, countries)
    }
}

// MARK: - REST decoding

private struct RESTEnvelope<T: Decodable>: Decodable {
    struct Message: Decodable { let code: Int?; let message: String }
    let success: Bool
    let errors: [Message]?
    let result: T?
}

// MARK: - GraphQL decoding

private struct GraphQLResponse: Decodable {
    struct GQLError: Decodable { let message: String }
    struct DataField: Decodable { let viewer: Viewer }
    struct Viewer: Decodable { let zones: [Zone] }
    struct Zone: Decodable { let groups: [Group] }
    struct Group: Decodable {
        let dimensions: Dimensions
        let sum: Sum
        let uniq: Uniq
    }
    struct Dimensions: Decodable {
        let date: String?
        let datetime: String?
    }
    struct Sum: Decodable {
        let requests: Int
        let pageViews: Int
        let bytes: Int
        let cachedBytes: Int
        let cachedRequests: Int
        let threats: Int
        let countryMap: [Country]?
    }
    struct Country: Decodable {
        let clientCountryName: String
        let requests: Int
    }
    struct Uniq: Decodable { let uniques: Int }

    let data: DataField?
    let errors: [GQLError]?
}

// MARK: - Helpers

enum Formatters {
    static let iso8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static let day: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar.utc
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}

extension Calendar {
    static let utc: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()
}
