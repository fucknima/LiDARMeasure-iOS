import Foundation
import simd

struct MeasurementDimensions: Equatable, Codable {
    var width: Float
    var height: Float
    var depth: Float

    func formatted(using unit: MeasurementUnit) -> String {
        "宽 \(unit.format(width))  高 \(unit.format(height))  深 \(unit.format(depth))"
    }
}

/// 单个世界坐标点，携带深度置信度。
struct Point3D {
    var value: SIMD3<Float>
    var confidence: Float
}

enum MeasurementQualityGrade: String, Codable {
    case excellent = "优秀"
    case good = "良好"
    case poor = "较差"
}

struct MeasurementQuality {
    let grade: MeasurementQualityGrade
    let score: Float
}

enum MeasurementQualityEvaluator {
    /// 综合跟踪状态、深度置信度、有效点数、距离与稳定度给出质量分。
    static func evaluate(
        trackingLimited: Bool,
        depthConfidence: Float,
        pointCount: Int,
        distanceMeters: Float?,
        stability: Float
    ) -> MeasurementQuality {
        var score: Float = 1
        if trackingLimited { score -= 0.3 }
        if depthConfidence < 0.8 { score -= 0.1 }
        if pointCount < 300 { score -= 0.15 }
        if let distance = distanceMeters {
            if distance < 0.2 { score -= 0.25 }
            if distance > 4 { score -= 0.2 }
            if distance >= 0.3, distance <= 3 { score += 0.1 }
        }
        if stability < 0.6 { score -= 0.2 }
        score = min(1, max(0, score))

        let grade: MeasurementQualityGrade
        if score >= 0.75 { grade = .excellent }
        else if score >= 0.45 { grade = .good }
        else { grade = .poor }
        return MeasurementQuality(grade: grade, score: score)
    }
}

struct MeasurementRecord: Identifiable, Codable {
    var id = UUID()
    var date: Date
    var mode: MeasurementMode
    var dimensions: MeasurementDimensions
    var unit: MeasurementUnit
    var distanceMeters: Float?
    var screenshotPath: String?
    var quality: String?

    var primaryText: String {
        if let distanceMeters {
            return "长度 \(unit.format(distanceMeters))"
        }
        return dimensions.formatted(using: unit)
    }
}
