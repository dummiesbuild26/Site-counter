import Foundation
import SwiftUI

// Shared by the macOS and iOS apps.

enum ChartMetric: String, CaseIterable, Identifiable {
    case pageViews = "Page Views"
    case visits = "Visits"
    case requests = "All Requests"
    case bandwidth = "Bandwidth"

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .pageViews: return .blue
        case .visits: return .purple
        case .requests: return .orange
        case .bandwidth: return .teal
        }
    }
}

extension Int {
    var compact: String { formatted(.number.notation(.compactName)) }
    var bytes: String { ByteCountFormatter.string(fromByteCount: Int64(self), countStyle: .file) }
}
