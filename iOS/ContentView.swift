import Charts
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: StatsStore
    @State private var showingSettings = false
    @State private var metric: ChartMetric = .pageViews

    var body: some View {
        NavigationStack {
            Group {
                if store.isConfigured {
                    dashboard
                } else {
                    onboarding
                }
            }
            .navigationTitle(store.isConfigured ? store.title : "Site Counter")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    domainMenu
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingSettings = true
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                }
            }
            .sheet(isPresented: $showingSettings) {
                SettingsSheet()
                    .environmentObject(store)
            }
        }
    }

    // MARK: Domain picker

    @ViewBuilder
    private var domainMenu: some View {
        if store.zones.count > 1 {
            Menu {
                Picker("Domain", selection: $store.selection) {
                    Text("All Domains").tag(StatsStore.allZones)
                    ForEach(store.zones) { Text($0.name).tag($0.id) }
                }
            } label: {
                Label("Domain", systemImage: "globe")
            }
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
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Open Settings") { showingSettings = true }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Dashboard

    private var dashboard: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Picker("Range", selection: $store.range) {
                    ForEach(StatsRange.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                infoRow

                if let note = store.webAnalyticsNote {
                    Label(note, systemImage: "info.circle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if let error = store.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(.red)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                }

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    StatTile(title: "Page Views", value: store.totalPageViews.compact, icon: "doc.text", tint: .blue)
                    StatTile(title: "Visits", value: store.totalVisits.compact, icon: "person.2", tint: .purple)
                    StatTile(title: "All Requests", value: store.totalRequests.compact, icon: "arrow.left.arrow.right", tint: .orange)
                    StatTile(title: "Bandwidth", value: store.totalBytes.bytes, icon: "arrow.down.circle", tint: .teal)
                    StatTile(title: "Cached", value: store.cacheRatio.formatted(.percent.precision(.fractionLength(1))), icon: "bolt", tint: .green)
                    StatTile(title: "Threats", value: store.totalThreats.compact, icon: "shield.lefthalf.filled", tint: .red)
                }

                chartSection

                if !store.countries.isEmpty {
                    countriesSection
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .refreshable { await store.reload() }
    }

    private var infoRow: some View {
        HStack(spacing: 8) {
            if store.selection == StatsStore.allZones {
                Text("\(store.zones.count) domains combined")
            } else if let plan = store.selectedZone?.plan {
                Text(plan)
            }
            if let status = store.selectedZone?.status {
                Text(status.capitalized)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background((status == "active" ? Color.green : Color.orange).opacity(0.2), in: Capsule())
            }
            Spacer()
            if store.isLoading {
                ProgressView()
            } else if let updated = store.lastUpdated {
                Text("Updated \(updated.formatted(date: .omitted, time: .shortened))")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
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
            }

            if store.series(metric).isEmpty {
                Text(store.isLoading ? "Loading…" : "No data for this period.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 200)
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
                .frame(height: 220)
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    private var countriesSection: some View {
        let top = Array(store.countries.prefix(10))
        let maxRequests = max(top.first?.requests ?? 1, 1)

        return VStack(alignment: .leading, spacing: 10) {
            Text("Top Countries").font(.headline)
            ForEach(top) { country in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("\(country.flag) \(country.name)")
                            .lineLimit(1)
                        Spacer()
                        Text(country.requests.compact)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .font(.subheadline)
                    GeometryReader { geo in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.orange.gradient)
                            .frame(width: geo.size.width * CGFloat(country.requests) / CGFloat(maxRequests))
                    }
                    .frame(height: 6)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }
}

struct StatTile: View {
    let title: String
    let value: String
    let icon: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: icon)
                .font(.caption)
                .foregroundStyle(tint)
            Text(value)
                .font(.system(.title2, design: .rounded).bold())
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }
}
