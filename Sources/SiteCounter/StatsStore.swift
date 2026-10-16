import Foundation
import SwiftUI

@MainActor
final class StatsStore: ObservableObject {
    @Published private(set) var points: [StatPoint] = []
    @Published private(set) var countries: [CountryStat] = []
    @Published private(set) var zone: ZoneInfo?
    @Published private(set) var accountName: String?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var lastUpdated: Date?

    @Published var range: StatsRange = .week {
        didSet { if range != oldValue { refresh() } }
    }

    @Published private(set) var zoneID: String
    @Published private(set) var accountID: String
    private var token: String

    private var refreshTask: Task<Void, Never>?
    private var autoRefreshTask: Task<Void, Never>?

    init() {
        zoneID = UserDefaults.standard.string(forKey: "zoneID") ?? ""
        accountID = UserDefaults.standard.string(forKey: "accountID") ?? ""
        token = Keychain.readToken() ?? ""
        startAutoRefresh()
    }

    var isConfigured: Bool { !zoneID.isEmpty && !token.isEmpty }
    var hasToken: Bool { !token.isEmpty }

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

    func save(token newToken: String, zoneID newZoneID: String, accountID newAccountID: String) {
        let trimmedToken = newToken.trimmingCharacters(in: .whitespacesAndNewlines)
        // An empty token field keeps the token already saved in the Keychain.
        if !trimmedToken.isEmpty, trimmedToken != token {
            token = trimmedToken
            Keychain.saveToken(trimmedToken)
        }
        zoneID = newZoneID.trimmingCharacters(in: .whitespacesAndNewlines)
        accountID = newAccountID.trimmingCharacters(in: .whitespacesAndNewlines)
        UserDefaults.standard.set(zoneID, forKey: "zoneID")
        UserDefaults.standard.set(accountID, forKey: "accountID")

        zone = nil
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
        let zoneID = zoneID
        let accountID = accountID
        let range = range

        do {
            async let stats = client.stats(zoneID: zoneID, range: range)
            async let zoneInfo = try? client.zoneInfo(zoneID: zoneID)
            async let account: String? = accountID.isEmpty ? nil : (try? client.accountName(accountID: accountID))

            let result = try await stats
            let info = await zoneInfo
            let name = await account
            guard !Task.isCancelled else { return }

            points = result.points
            countries = result.countries
            zone = info
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
