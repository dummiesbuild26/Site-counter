import SwiftUI

@main
struct SiteCounterIOSApp: App {
    @StateObject private var store = StatsStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active { store.refresh() }
        }
    }
}
