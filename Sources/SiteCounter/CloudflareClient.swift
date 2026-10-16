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

struct ZoneInfo: Identifiable, Hashable {
    let id: String
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

    /// Every domain the token can see, optionally limited to one account.
    func listZones(accountID: String?) async throws -> [ZoneInfo] {
        struct Result: Decodable {
            struct Plan: Decodable { let name: String }
            let id: String
            let name: String
            let status: String
            let plan: Plan?
        }
        var zones: [ZoneInfo] = []
        var page = 1
        while true {
            var query = [
                URLQueryItem(name: "per_page", value: "50"),
                URLQueryItem(name: "page", value: String(page)),
            ]
            if let accountID, !accountID.isEmpty {
                query.append(URLQueryItem(name: "account.id", value: accountID))
            }
            let results: [Result] = try await get("zones", query: query)
            zones += results.map { ZoneInfo(id: $0.id, name: $0.name, status: $0.status, plan: $0.plan?.name) }
            if results.count < 50 { break }
            page += 1
        }
        return zones.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func accountName(accountID: String) async throws -> String {
        struct Result: Decodable { let name: String }
        let result: Result = try await get("accounts/\(accountID)")
        return result.name
    }

    private func get<T: Decodable>(_ path: String, query: [URLQueryItem] = []) async throws -> T {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        var request = URLRequest(url: components.url!)
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

    /// Traffic for one or more zones. With several zones, buckets for the
    /// same time are added together.
    func stats(zoneIDs: [String], range: StatsRange) async throws -> (points: [StatPoint], countries: [CountryStat]) {
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
        let variables: [String: Any]
        let now = Date()

        if range.isHourly {
            query = """
            query ($zoneTags: [string!], $since: Time, $until: Time) {
              viewer {
                zones(filter: { zoneTag_in: $zoneTags }) {
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
                "zoneTags": zoneIDs,
                "since": Formatters.iso8601.string(from: since),
                "until": Formatters.iso8601.string(from: now),
            ]
        } else {
            query = """
            query ($zoneTags: [string!], $since: Date, $until: Date) {
              viewer {
                zones(filter: { zoneTag_in: $zoneTags }) {
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
                "zoneTags": zoneIDs,
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
        guard let zones = decoded.data?.viewer.zones, !zones.isEmpty else {
            throw CloudflareError(message: "No analytics found. Check that the token has Analytics Read access to this domain.")
        }

        var countryTotals: [String: Int] = [:]
        let perZone: [StatPoint] = zones.flatMap(\.groups).compactMap { group in
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

        let points = Dictionary(grouping: perZone, by: \.date)
            .map { date, items in
                StatPoint(
                    date: date,
                    requests: items.reduce(0) { $0 + $1.requests },
                    pageViews: items.reduce(0) { $0 + $1.pageViews },
                    uniques: items.reduce(0) { $0 + $1.uniques },
                    bytes: items.reduce(0) { $0 + $1.bytes },
                    cachedBytes: items.reduce(0) { $0 + $1.cachedBytes },
                    cachedRequests: items.reduce(0) { $0 + $1.cachedRequests },
                    threats: items.reduce(0) { $0 + $1.threats }
                )
            }
            .sorted { $0.date < $1.date }

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
