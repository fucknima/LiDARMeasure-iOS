import Foundation

enum MeasurementMode: String, CaseIterable, Identifiable, Codable {
    case automatic
    case boxSelection
    case manualLength
    case manualDimensions
    case roomScan

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .automatic: return "自动"
        case .boxSelection: return "框选"
        case .manualLength: return "长度"
        case .manualDimensions: return "长宽高"
        case .roomScan: return "房间"
        }
    }

    var usesPointCloud: Bool {
        self == .automatic || self == .boxSelection
    }
}
