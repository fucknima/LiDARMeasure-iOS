import Foundation

enum MeasurementUnit: String, CaseIterable, Identifiable, Codable {
    case millimeter
    case centimeter
    case meter
    case inch

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .millimeter: return "毫米 (mm)"
        case .centimeter: return "厘米 (cm)"
        case .meter: return "米 (m)"
        case .inch: return "英寸 (inch)"
        }
    }

    var symbol: String {
        switch self {
        case .millimeter: return "mm"
        case .centimeter: return "cm"
        case .meter: return "m"
        case .inch: return "in"
        }
    }

    /// App 内部统一使用米（meters），仅在展示时转换。
    func value(fromMeters meters: Float) -> Float {
        switch self {
        case .millimeter: return meters * 1000
        case .centimeter: return meters * 100
        case .meter: return meters
        case .inch: return meters * 100 / 2.54
        }
    }

    func format(_ meters: Float) -> String {
        String(format: "%.1f %@", value(fromMeters: meters), symbol)
    }
}
