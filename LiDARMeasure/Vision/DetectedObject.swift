import CoreGraphics
import Foundation

/// 检测结果。boundingBox 为归一化坐标，原点左下（Vision 坐标系）。
struct DetectedObject: Identifiable, Equatable {
    var id: UUID
    let label: String
    let confidence: Float
    var boundingBox: CGRect

    var center: CGPoint {
        CGPoint(x: boundingBox.midX, y: boundingBox.midY)
    }

    var area: CGFloat {
        boundingBox.width * boundingBox.height
    }
}
