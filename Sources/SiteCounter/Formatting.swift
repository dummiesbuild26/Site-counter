import Foundation
import SwiftUI

// Shared by the macOS and iOS apps.

enum ChartMetric: String, CaseIterable, Identifiable {
    case requests = "Requests"
    case pageViews = "Page Views"
    case uniques = "Visitors"
    case bandwidth = "Bandwidth"

    var id: String { rawValue }

    func value(_ point: StatPoint) -> Int {
        switch self {
        case .requests: return point.requests
        case .pageViews: return point.pageViews
        case .uniques: return point.uniques
        case .bandwidth: return point.bytes
        }
    }

    var color: Color {
        switch self {
        case .requests: return .orange
        case .pageViews: return .blue
        case .uniques: return .purple
        case .bandwidth: return .teal
        }
    }
}

extension Int {
    var compact: String { formatted(.number.notation(.compactName)) }
    var bytes: String { ByteCountFormatter.string(fromByteCount: Int64(self), countStyle: .file) }
}
