import Foundation

/// 自动测量状态机。
enum AutoMeasureState: Equatable {
    case searching
    case detected
    case segmenting
    case collectingDepth
    case measuring
    case stabilizing
    case locked
    case failed(AutoMeasureError)
}

enum AutoMeasureError: Equatable, LocalizedError {
    case modelUnavailable
    case modelOutputMismatch
    case inferenceFailed
    case noObject
    case lowConfidence
    case objectTooSmall
    case objectClipped
    case segmentationFailed
    case maskDecodeFailed
    case noDepth
    case insufficientPoints
    case unstableGeometry

    var errorDescription: String? { message }

    var message: String {
        switch self {
        case .modelUnavailable: return "检测模型加载失败"
        case .modelOutputMismatch: return "模型输出格式不匹配，请检查 Debug 日志"
        case .inferenceFailed: return "模型推理失败"
        case .noObject: return "未检测到支持的目标，可点击框选"
        case .lowConfidence: return "目标置信度过低，请靠近"
        case .objectTooSmall: return "目标太远，请靠近"
        case .objectClipped: return "物体未完整进入画面"
        case .segmentationFailed: return "前景分割失败，可尝试框选"
        case .maskDecodeFailed: return "目标 mask 解码失败"
        case .noDepth: return "LiDAR 深度数据不足，请靠近"
        case .insufficientPoints: return "物体区域有效深度点过少"
        case .unstableGeometry: return "几何不稳定，保持手机稳定"
        }
    }
}
