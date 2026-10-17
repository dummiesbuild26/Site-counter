import Charts
import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var store: StatsStore
    @State private var showingSettings = false
    @State private var metric: ChartMetric = .pageViews

    var body: some View {
        Group {
            if store.isConfigured {
                dashboard
            } else {
                onboarding
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                if !store.zones.isEmpty {
                    Picker("Domain", selection: $store.selection) {
                        if store.zones.count > 1 {
                            Text("All Domains").tag(StatsStore.allZones)
                            Divider()
                        }
                        ForEach(store.zones) { Text($0.name).tag($0.id) }
                    }
                    .fixedSize()
                }
            }
            ToolbarItem(placement: .principal) {
                Picker("Range", selection: $store.range) {
                    ForEach(StatsRange.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .disabled(!store.isConfigured)
            }
            ToolbarItem {
                Button {
                    store.refresh()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(!store.isConfigured || store.isLoading)
            }
            ToolbarItem {
                Button {
                    showingSettings = true
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView(onDone: { showingSettings = false })
                .environmentObject(store)
        }
    }

    // MARK: Onboarding

    private var onboarding: some View {
        VStack(spacing: 16) {
            Image(systemName: "cloud")
                .font(.system(size: 56))
                .foregroundStyle(.orange)
            Text("Connect to Cloudflare")
                .font(.title2.bold())
            Text("Add your Cloudflare API token to see stats for all your domains.")
                .foregroundStyle(.secondary)
            Button("Open Settings…") { showingSettings = true }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Dashboard

    private var dashboard: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                if let note = store.webAnalyticsNote {
                    Label(note, systemImage: "info.circle")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                if let error = store.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                        .textSelection(.enabled)
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], spacing: 12) {
                    StatCard(title: "Page Views", value: store.totalPageViews.compact, icon: "doc.text", tint: .blue)
                    StatCard(title: "Visits", value: store.totalVisits.compact, icon: "person.2", tint: .purple)
                    StatCard(title: "All Requests", value: store.totalRequests.compact, icon: "arrow.left.arrow.right", tint: .orange)
                    StatCard(title: "Bandwidth", value: store.totalBytes.bytes, icon: "arrow.down.circle", tint: .teal)
                    StatCard(title: "Cached", value: store.cacheRatio.formatted(.percent.precision(.fractionLength(1))), icon: "bolt", tint: .green)
                    StatCard(title: "Threats Blocked", value: store.totalThreats.compact, icon: "shield.lefthalf.filled", tint: .red)
                }

                chartSection

                if !store.countries.isEmpty {
                    countriesSection
                }
            }
            .padding(24)
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text(store.title)
                    .font(.largeTitle.bold())
                HStack(spacing: 8) {
                    if let account = store.accountName {
                        Label(account, systemImage: "person.crop.circle")
                    }
                    if store.selection == StatsStore.allZones {
                        Text("\(store.zones.count) domains combined")
                    }
                    if let plan = store.selectedZone?.plan {
                        Text(plan)
                    }
                    if let status = store.selectedZone?.status {
                        Text(status.capitalized)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background((status == "active" ? Color.green : Color.orange).opacity(0.2), in: Capsule())
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            Spacer()
            if store.isLoading {
                ProgressView().controlSize(.small)
            } else if let updated = store.lastUpdated {
                Text("Updated \(updated.formatted(date: .omitted, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var chartSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Traffic").font(.headline)
                Spacer()
                Picker("Metric", selection: $metric) {
                    ForEach(ChartMetric.allCases) { Text($0.rawValue).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
            }

            if store.series(metric).isEmpty {
                Text(store.isLoading ? "Loading…" : "No data for this period.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 240)
            } else {
                Chart(store.series(metric)) { point in
                    let unit: Calendar.Component = store.range.isHourly ? .hour : .day
                    AreaMark(
                        x: .value("Time", point.date, unit: unit),
                        y: .value(metric.rawValue, point.value)
                    )
                    .foregroundStyle(metric.color.opacity(0.2).gradient)
                    .interpolationMethod(.monotone)

                    LineMark(
                        x: .value("Time", point.date, unit: unit),
                        y: .value(metric.rawValue, point.value)
                    )
                    .foregroundStyle(metric.color)
                    .interpolationMethod(.monotone)
                }
                .chartYAxis {
                    AxisMarks { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let v = value.as(Int.self) {
                                Text(metric == .bandwidth ? v.bytes : v.compact)
                            }
                        }
                    }
                }
                .frame(height: 260)
            }
        }
        .padding(16)
        .background(Color.card, in: RoundedRectangle(cornerRadius: 12))
    }

    private var countriesSection: some View {
        let top = Array(store.countries.prefix(10))
        let maxRequests = max(top.first?.requests ?? 1, 1)

        return VStack(alignment: .leading, spacing: 10) {
            Text("Top Countries").font(.headline)
            ForEach(top) { country in
                HStack {
                    Text(country.flag)
                    Text(country.name)
                        .frame(width: 180, alignment: .leading)
                        .lineLimit(1)
                    GeometryReader { geo in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.orange.gradient)
                            .frame(width: geo.size.width * CGFloat(country.requests) / CGFloat(maxRequests))
                    }
                    .frame(height: 10)
                    Text(country.requests.compact)
                        .monospacedDigit()
                        .frame(width: 60, alignment: .trailing)
                }
            }
        }
        .padding(16)
        .background(Color.card, in: RoundedRectangle(cornerRadius: 12))
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.subheadline)
                .foregroundStyle(tint)
            Text(value)
                .font(.system(.title, design: .rounded).bold())
                .monospacedDigit()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.card, in: RoundedRectangle(cornerRadius: 12))
    }
}

extension Color {
    static let card = Color(nsColor: .controlBackgroundColor)
}
