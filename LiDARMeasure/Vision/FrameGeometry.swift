import ARKit
import CoreGraphics
import CoreVideo
import Foundation

/// 一帧的几何信息，供所有坐标转换共享（任务书第 36 条）。
///
/// 所有转换必须通过 CoordinateMapper 完成，禁止在多个文件各自发明坐标换算。
struct FrameGeometry {
    /// capturedImage 像素尺寸（横向，如 1920x1440）。
    let cameraResolution: CGSize
    /// depthMap 像素尺寸（如 256x192）。
    let depthResolution: CGSize
    /// ARView viewport 尺寸（点）。
    let viewportSize: CGSize
    /// 图像方向（VNImageRequestHandler 使用）。
    let orientation: CGImagePropertyOrientation
    /// 图像（左下原点归一化）→ 视图坐标。
    let displayTransform: CGAffineTransform

    static func make(frame: ARFrame, viewportSize: CGSize) -> FrameGeometry {
        FrameGeometry(
            cameraResolution: CGSize(
                width: CVPixelBufferGetWidth(frame.capturedImage),
                height: CVPixelBufferGetHeight(frame.capturedImage)
            ),
            depthResolution: CGSize(
                width: DepthReader.bestDepthData(from: frame).map { CVPixelBufferGetWidth($0.depthMap) } ?? 0,
                height: DepthReader.bestDepthData(from: frame).map { CVPixelBufferGetHeight($0.depthMap) } ?? 0
            ),
            viewportSize: viewportSize,
            orientation: .right,
            displayTransform: frame.displayTransform(for: .portrait, viewportSize: viewportSize)
        )
    }
}
