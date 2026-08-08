import CoreGraphics
import CoreVideo
import Foundation

/// 分割检测结果。
///
/// 坐标约定：boundingBox 为模型空间归一化框（左下原点，640 输入空间，
/// scaleFill 下与「显示方向图像」归一化空间一致）；mask 为模型空间
/// 160x160 二值像素数据（左上原点），采样时按归一化坐标查询。
struct SegmentedObject: Identifiable {
    /// 当前帧临时 ID（每帧重新生成）。
    let frameID: UUID
    /// 跨帧稳定 ID（由 ObjectTracker 维护）。
    var stableID: UUID
    let label: String
    let confidence: Float
    let classIndex: Int
    /// 模型空间归一化框（左下原点）。
    var boundingBox: CGRect
    /// 二值实例 mask（160x160，OneComponent8，左上原点）。
    let mask: CVPixelBuffer
    /// mask 非零像素占比（0~1）。
    let maskCoverage: Float

    var id: UUID { frameID }

    var center: CGPoint {
        CGPoint(x: boundingBox.midX, y: boundingBox.midY)
    }
}
