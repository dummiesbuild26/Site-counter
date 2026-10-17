import Foundation
import SwiftUI

struct ChartPoint: Identifiable {
    let date: Date
    let value: Int
    var id: Date { date }
}

@MainActor
final class StatsStore: ObservableObject {
    /// All requests reaching Cloudflare (zone traffic analytics).
    @Published private(set) var points: [StatPoint] = []
    /// Page views and visits from Web Analytics, when it's set up.
    @Published private(set) var visitPoints: [VisitPoint] = []
    @Published private(set) var hasWebAnalytics = false
    /// Why Web Analytics numbers aren't shown, if they aren't.
    @Published private(set) var webAnalyticsNote: String?
    @Published private(set) var webCountries: [CountryStat] = []
    @Published private(set) var trafficCountries: [CountryStat] = []
    @Published private(set) var zones: [ZoneInfo] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var lastUpdated: Date?

    @Published var range: StatsRange = .week {
        didSet { if range != oldValue { refresh() } }
    }

    /// A zone ID, or `StatsStore.allZones` to add every domain together.
    @Published var selection: String {
        didSet {
            guard selection != oldValue else { return }
            UserDefaults.standard.set(selection, forKey: "selectedZone")
            clearStats()
            refresh()
        }
    }

    static let allZones = "all"

    @Published private(set) var accountID: String
    private var token: String

    private var refreshTask: Task<Void, Never>?
    private var autoRefreshTask: Task<Void, Never>?

    init() {
        // "zoneID" is where versions before multi-domain support kept the zone.
        selection = UserDefaults.standard.string(forKey: "selectedZone")
            ?? UserDefaults.standard.string(forKey: "zoneID") ?? ""
        accountID = UserDefaults.standard.string(forKey: "accountID") ?? ""
        token = Keychain.readToken() ?? ""
        startAutoRefresh()
    }

    var isConfigured: Bool { !token.isEmpty }
    var hasToken: Bool { !token.isEmpty }

    var selectedZone: ZoneInfo? { zones.first { $0.id == selection } }
    var accountName: String? { (selectedZone ?? zones.first)?.accountName }

    var title: String {
        if selection == Self.allZones { return "All Domains" }
        return selectedZone?.name ?? "Your Site"
    }

    // MARK: Totals

    /// Page views from Web Analytics, or Cloudflare's page-view estimate from
    /// zone traffic when Web Analytics isn't available.
    var totalPageViews: Int {
        hasWebAnalytics ? visitPoints.reduce(0) { $0 + $1.pageViews } : points.reduce(0) { $0 + $1.pageViews }
    }

    /// Visits from Web Analytics, or unique IPs from zone traffic as a fallback.
    var totalVisits: Int {
        hasWebAnalytics ? visitPoints.reduce(0) { $0 + $1.visits } : points.reduce(0) { $0 + $1.uniques }
    }

    var totalRequests: Int { points.reduce(0) { $0 + $1.requests } }
    var totalBytes: Int { points.reduce(0) { $0 + $1.bytes } }
    var totalThreats: Int { points.reduce(0) { $0 + $1.threats } }

    var cacheRatio: Double {
        let requests = totalRequests
        guard requests > 0 else { return 0 }
        return Double(points.reduce(0) { $0 + $1.cachedRequests }) / Double(requests)
    }

    var countries: [CountryStat] { hasWebAnalytics ? webCountries : trafficCountries }

    func series(_ metric: ChartMetric) -> [ChartPoint] {
        switch metric {
        case .pageViews:
            return hasWebAnalytics
                ? visitPoints.map { ChartPoint(date: $0.date, value: $0.pageViews) }
                : points.map { ChartPoint(date: $0.date, value: $0.pageViews) }
        case .visits:
            return hasWebAnalytics
                ? visitPoints.map { ChartPoint(date: $0.date, value: $0.visits) }
                : points.map { ChartPoint(date: $0.date, value: $0.uniques) }
        case .requests:
            return points.map { ChartPoint(date: $0.date, value: $0.requests) }
        case .bandwidth:
            return points.map { ChartPoint(date: $0.date, value: $0.bytes) }
        }
    }

    // MARK: Actions

    func save(token newToken: String, accountID newAccountID: String) {
        let trimmedToken = newToken.trimmingCharacters(in: .whitespacesAndNewlines)
        // An empty token field keeps the token already saved in the Keychain.
        if !trimmedToken.isEmpty, trimmedToken != token {
            token = trimmedToken
            Keychain.saveToken(trimmedToken)
        }
        accountID = newAccountID.trimmingCharacters(in: .whitespacesAndNewlines)
        UserDefaults.standard.set(accountID, forKey: "accountID")

        zones = []
        clearStats()
        refresh()
    }

    func refresh() {
        refreshTask?.cancel()
        guard isConfigured else {
            errorMessage = nil
            return
        }
        refreshTask = Task { await load() }
    }

    /// Refreshes and waits for it to finish (used by pull-to-refresh).
    func reload() async {
        refresh()
        await refreshTask?.value
    }

    private func clearStats() {
        points = []
        visitPoints = []
        webCountries = []
        trafficCountries = []
        hasWebAnalytics = false
        webAnalyticsNote = nil
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }

        let client = CloudflareClient(token: token)
        let range = range

        do {
            let found = try await client.listZones(accountID: accountID)
            guard !Task.isCancelled else { return }
            zones = found
            guard !found.isEmpty else {
                throw CloudflareError(message: "No domains found. Check that the token has Zone Read access for all zones.")
            }

            // Fall back to the first domain if nothing (or a removed domain) is selected.
            if selection != Self.allZones, !found.contains(where: { $0.id == selection }) {
                selection = found[0].id
                return // Changing the selection starts a new refresh.
            }
            let selected = selection == Self.allZones ? found : found.filter { $0.id == selection }

            async let traffic = Self.loadTraffic(client: client, zones: selected, range: range)
            async let web = Self.loadWebAnalytics(client: client, zones: selected, range: range)
            let trafficResult = await traffic
            let webResult = await web
            guard !Task.isCancelled else { return }

            switch webResult {
            case .success(let data):
                visitPoints = data.points
                webCountries = data.countries
                hasWebAnalytics = true
                webAnalyticsNote = nil
            case .failure(let error):
                visitPoints = []
                webCountries = []
                hasWebAnalytics = false
                webAnalyticsNote = error.localizedDescription
            }

            switch trafficResult {
            case .success(let data):
                points = data.points
                trafficCountries = data.countries
            case .failure(let error):
                points = []
                trafficCountries = []
                if !hasWebAnalytics { throw error }
            }

            lastUpdated = Date()
            errorMessage = nil
        } catch {
            guard !Task.isCancelled else { return }
            if (error as? URLError)?.code == .cancelled { return }
            errorMessage = error.localizedDescription
        }
    }

    private static func loadTraffic(client: CloudflareClient, zones: [ZoneInfo], range: StatsRange) async -> Result<(points: [StatPoint], countries: [CountryStat]), Error> {
        do {
            return .success(try await client.stats(zoneIDs: zones.map(\.id), range: range))
        } catch {
            return .failure(error)
        }
    }

    private static func loadWebAnalytics(client: CloudflareClient, zones: [ZoneInfo], range: StatsRange) async -> Result<(points: [VisitPoint], countries: [CountryStat]), Error> {
        // Web Analytics belongs to accounts, so query each account separately.
        let byAccount = Dictionary(grouping: zones) { $0.accountID ?? "" }
        var allPoints: [Date: VisitPoint] = [:]
        var countryTotals: [String: Int] = [:]
        var foundSite = false

        do {
            for (accountID, accountZones) in byAccount where !accountID.isEmpty {
                let sites = try await client.listWebAnalyticsSites(accountID: accountID)
                let tags = sites.filter { site in accountZones.contains { site.matches($0) } }.map(\.siteTag)
                guard !tags.isEmpty else { continue }
                foundSite = true

                let result = try await client.webAnalytics(accountID: accountID, siteTags: tags, range: range)
                for point in result.points {
                    let existing = allPoints[point.date]
                    allPoints[point.date] = VisitPoint(
                        date: point.date,
                        pageViews: point.pageViews + (existing?.pageViews ?? 0),
                        visits: point.visits + (existing?.visits ?? 0)
                    )
                }
                for country in result.countries {
                    countryTotals[country.code, default: 0] += country.requests
                }
            }
        } catch {
            return .failure(CloudflareError(message: "Web Analytics couldn't be loaded, so page views are estimated from all traffic. Add Account → Account Analytics → Read to your API token. (\(error.localizedDescription))"))
        }

        guard foundSite else {
            return .failure(CloudflareError(message: "Web Analytics isn't set up for this domain, so page views are estimated from all traffic."))
        }
        let points = allPoints.values.sorted { $0.date < $1.date }
        let countries = countryTotals
            .map { CountryStat(code: $0.key, requests: $0.value) }
            .sorted { $0.requests > $1.requests }
        return .success((points, countries))
    }

    private func startAutoRefresh() {
        autoRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.refresh()
                try? await Task.sleep(nanoseconds: 5 * 60 * 1_000_000_000)
            }
        }
    }
}
