import Foundation
import SwiftUI

@MainActor
final class StatsStore: ObservableObject {
    @Published private(set) var points: [StatPoint] = []
    @Published private(set) var countries: [CountryStat] = []
    @Published private(set) var zones: [ZoneInfo] = []
    @Published private(set) var accountName: String?
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
            points = []
            countries = []
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

    var title: String {
        if selection == Self.allZones { return "All Domains" }
        return selectedZone?.name ?? "Your Site"
    }

    // MARK: Totals

    var totalRequests: Int { points.reduce(0) { $0 + $1.requests } }
    var totalPageViews: Int { points.reduce(0) { $0 + $1.pageViews } }
    var totalBytes: Int { points.reduce(0) { $0 + $1.bytes } }
    var totalThreats: Int { points.reduce(0) { $0 + $1.threats } }

    /// Sum of per-bucket uniques. Cloudflare can't de-duplicate visitors
    /// across buckets, so this is an upper bound for multi-bucket ranges.
    var totalUniques: Int { points.reduce(0) { $0 + $1.uniques } }

    var cacheRatio: Double {
        let requests = totalRequests
        guard requests > 0 else { return 0 }
        return Double(points.reduce(0) { $0 + $1.cachedRequests }) / Double(requests)
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
        accountName = nil
        points = []
        countries = []
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

    private func load() async {
        isLoading = true
        defer { isLoading = false }

        let client = CloudflareClient(token: token)
        let accountID = accountID
        let range = range

        do {
            async let account: String? = accountID.isEmpty ? nil : (try? client.accountName(accountID: accountID))

            let found = try await client.listZones(accountID: accountID)
            guard !Task.isCancelled else { return }
            zones = found
            guard !found.isEmpty else {
                throw CloudflareError(message: "No domains found. Check that the token has Zone Read access and that the Account ID is correct.")
            }

            // Fall back to the first domain if nothing (or a removed domain) is selected.
            if selection != Self.allZones, !found.contains(where: { $0.id == selection }) {
                selection = found[0].id
                return // Changing the selection starts a new refresh.
            }
            let zoneIDs = selection == Self.allZones ? found.map(\.id) : [selection]

            let result = try await client.stats(zoneIDs: zoneIDs, range: range)
            let name = await account
            guard !Task.isCancelled else { return }

            points = result.points
            countries = result.countries
            accountName = name
            lastUpdated = Date()
            errorMessage = nil
        } catch {
            guard !Task.isCancelled else { return }
            if (error as? URLError)?.code == .cancelled { return }
            errorMessage = error.localizedDescription
        }
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
