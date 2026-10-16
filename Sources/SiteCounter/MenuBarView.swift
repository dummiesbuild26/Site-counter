import AppKit
import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject private var store: StatsStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(store.isConfigured ? store.title : "Site Counter")
                .font(.headline)

            if store.isConfigured {
                Text(store.range.rawValue)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                    row("Requests", store.totalRequests.compact)
                    row("Page Views", store.totalPageViews.compact)
                    row("Visitors", store.totalUniques.compact)
                    row("Bandwidth", store.totalBytes.bytes)
                    row("Threats", store.totalThreats.compact)
                }
                if let error = store.errorMessage {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
            } else {
                Text("Not connected yet.").foregroundStyle(.secondary)
            }

            Divider()

            HStack {
                Button("Open Dashboard") {
                    openWindow(id: "dashboard")
                    NSApp.activate(ignoringOtherApps: true)
                }
                Button("Refresh") { store.refresh() }
                    .disabled(!store.isConfigured)
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
            }
        }
        .padding(14)
        .frame(width: 280)
    }

    private func row(_ title: String, _ value: String) -> some View {
        GridRow {
            Text(title).foregroundStyle(.secondary)
            Text(value).monospacedDigit().bold()
        }
    }
}
