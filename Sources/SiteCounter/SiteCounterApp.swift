import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Needed so the app gets a Dock icon and focus when launched via `swift run`.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@main
struct SiteCounterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = StatsStore()

    var body: some Scene {
        WindowGroup("Site Counter", id: "dashboard") {
            DashboardView()
                .environmentObject(store)
                .frame(minWidth: 780, minHeight: 600)
        }
        .commands {
            CommandGroup(after: .toolbar) {
                Button("Refresh") { store.refresh() }
                    .keyboardShortcut("r")
            }
        }

        Settings {
            SettingsView()
                .environmentObject(store)
        }

        MenuBarExtra {
            MenuBarView()
                .environmentObject(store)
        } label: {
            Label {
                Text(store.isConfigured ? store.totalRequests.compact : "")
            } icon: {
                Image(systemName: "chart.bar.xaxis")
            }
            .labelStyle(.titleAndIcon)
        }
        .menuBarExtraStyle(.window)
    }
}
