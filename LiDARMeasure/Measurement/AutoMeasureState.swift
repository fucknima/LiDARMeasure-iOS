import Foundation

/// 自动测量状态机。
enum AutoMeasureState: Equatable {
    case searching
    case detected
    case measuring
    case stabilizing
    case locked
    case failed(AutoMeasureError)
}

enum AutoMeasureError: Equatable {
    case modelUnavailable
    case noObject
    case lowConfidence
    case objectTooSmall
    case objectClipped
    case segmentationFailed
    case noDepth
    case insufficientPoints
    case unstableGeometry
}

extension AutoMeasureError {
    var message: String {
        switch self {
        case .modelUnavailable: return "检测模型加载失败"
        case .noObject: return "未检测到支持的目标，可点击框选"
        case .lowConfidence: return "目标置信度过低，请靠近"
        case .objectTooSmall: return "目标太远，请靠近"
        case .objectClipped: return "物体未完整进入画面"
        case .segmentationFailed: return "前景分割失败，可尝试框选"
        case .noDepth: return "LiDAR 深度数据不足，请靠近"
        case .insufficientPoints: return "物体区域有效深度点过少"
        case .unstableGeometry: return "几何不稳定，保持手机稳定"
        }
    }
}
