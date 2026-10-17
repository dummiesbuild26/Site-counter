import Foundation

// Cloudflare Web Analytics: page views and visits from real browsers, the
// numbers shown on the dashboard's Web Analytics page. Unlike zone traffic,
// these leave out bots, images, scripts and other non-page requests.

struct VisitPoint: Identifiable {
    let date: Date
    let pageViews: Int
    let visits: Int

    var id: Date { date }
}

struct WebAnalyticsSite {
    let siteTag: String
    let host: String?
    let zoneTag: String?
    let zoneName: String?

    func matches(_ zone: ZoneInfo) -> Bool {
        if zoneTag == zone.id || zoneName == zone.name { return true }
        guard let host else { return false }
        return host == zone.name || host.hasSuffix("." + zone.name)
    }
}

extension CloudflareClient {
    func listWebAnalyticsSites(accountID: String) async throws -> [WebAnalyticsSite] {
        struct Result: Decodable {
            struct Ruleset: Decodable {
                let zone_tag: String?
                let zone_name: String?
            }
            let site_tag: String
            let host: String?
            let ruleset: Ruleset?
        }
        let results: [Result] = try await get(
            "accounts/\(accountID)/rum/site_info/list",
            query: [URLQueryItem(name: "per_page", value: "100")]
        )
        return results.map {
            WebAnalyticsSite(siteTag: $0.site_tag, host: $0.host, zoneTag: $0.ruleset?.zone_tag, zoneName: $0.ruleset?.zone_name)
        }
    }

    /// Page views and visits for the given Web Analytics sites, with bots
    /// left out like the dashboard does.
    func webAnalytics(accountID: String, siteTags: [String], range: StatsRange) async throws -> (points: [VisitPoint], countries: [CountryStat]) {
        do {
            return try await webAnalytics(accountID: accountID, siteTags: siteTags, range: range, excludeBots: true)
        } catch let error as GraphQLQueryError {
            // Fall back if this account's schema doesn't offer the bot filter.
            _ = error
            return try await webAnalytics(accountID: accountID, siteTags: siteTags, range: range, excludeBots: false)
        }
    }

    private func webAnalytics(accountID: String, siteTags: [String], range: StatsRange, excludeBots: Bool) async throws -> (points: [VisitPoint], countries: [CountryStat]) {
        let now = Date()
        let since: Date
        if range.isHourly {
            since = now.addingTimeInterval(-24 * 3600)
        } else {
            let days = range == .week ? 6 : 29
            let start = Calendar.utc.date(byAdding: .day, value: -days, to: now)!
            since = Calendar.utc.startOfDay(for: start)
        }

        var conditions: [[String: Any]] = [
            ["datetime_geq": Formatters.iso8601.string(from: since), "datetime_leq": Formatters.iso8601.string(from: now)],
            ["OR": siteTags.map { ["siteTag": $0] }],
        ]
        if excludeBots { conditions.append(["bot": 0]) }

        let bucket = range.isHourly ? "datetimeHour" : "date"
        let query = """
        query ($accountTag: string!, $filter: AccountRumPageloadEventsAdaptiveGroupsFilter_InputObject) {
          viewer {
            accounts(filter: { accountTag: $accountTag }) {
              series: rumPageloadEventsAdaptiveGroups(limit: 5000, filter: $filter) {
                count
                sum { visits }
                dimensions { bucket: \(bucket) }
              }
              countries: rumPageloadEventsAdaptiveGroups(limit: 50, filter: $filter, orderBy: [count_DESC]) {
                count
                dimensions { countryName }
              }
            }
          }
        }
        """
        let variables: [String: Any] = ["accountTag": accountID, "filter": ["AND": conditions]]
        let data = try await graphQL(query: query, variables: variables)

        struct Response: Decodable {
            struct GQLError: Decodable { let message: String }
            struct DataField: Decodable { let viewer: Viewer }
            struct Viewer: Decodable { let accounts: [Account] }
            struct Account: Decodable {
                let series: [Series]
                let countries: [Country]
            }
            struct Series: Decodable {
                struct Sum: Decodable { let visits: Int }
                struct Dimensions: Decodable { let bucket: String }
                let count: Int
                let sum: Sum
                let dimensions: Dimensions
            }
            struct Country: Decodable {
                struct Dimensions: Decodable { let countryName: String }
                let count: Int
                let dimensions: Dimensions
            }
            let data: DataField?
            let errors: [GQLError]?
        }

        let decoded: Response
        do {
            decoded = try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw CloudflareError(message: "Could not read the Web Analytics response.")
        }
        if let errors = decoded.errors, !errors.isEmpty {
            throw GraphQLQueryError(message: errors.map(\.message).joined(separator: "\n"))
        }
        guard let account = decoded.data?.viewer.accounts.first else {
            return ([], [])
        }

        let points = account.series.compactMap { row -> VisitPoint? in
            let raw = row.dimensions.bucket
            guard let date = Formatters.iso8601.date(from: raw) ?? Formatters.day.date(from: raw) else { return nil }
            return VisitPoint(date: date, pageViews: row.count, visits: row.sum.visits)
        }
        .sorted { $0.date < $1.date }

        let countries = account.countries
            .filter { !$0.dimensions.countryName.isEmpty }
            .map { CountryStat(code: $0.dimensions.countryName, requests: $0.count) }
        return (points, countries)
    }
}

/// An error reported by the GraphQL API itself (for example a field this
/// account can't use), as opposed to a network or permission failure.
struct GraphQLQueryError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
