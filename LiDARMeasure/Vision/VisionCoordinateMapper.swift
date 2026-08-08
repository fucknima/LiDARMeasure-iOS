import CoreGraphics
import Foundation

/// Vision / Camera / Depth / View 坐标统一换算。
///
/// 约定：
/// - Vision 检测框：归一化，原点左下（Vision 坐标系）
/// - 深度图 / 视图采样：归一化，原点左上
/// - mask / 深度图：像素数据，原点左上
enum VisionCoordinateMapper {
    /// Vision 左下原点归一化 box → 左上原点归一化 box。
    static func topLeft(_ box: CGRect) -> CGRect {
        CGRect(x: box.minX, y: 1 - box.maxY, width: box.width, height: box.height)
    }

    /// 左上原点归一化 box → Vision 左下原点归一化 box。
    static func bottomLeft(_ box: CGRect) -> CGRect {
        CGRect(x: box.minX, y: 1 - box.maxY, width: box.width, height: box.height)
    }

    /// 视图点 → 左上原点归一化。
    static func normalized(_ point: CGPoint, in size: CGSize) -> CGPoint {
        guard size.width > 0, size.height > 0 else { return .zero }
        return CGPoint(x: point.x / size.width, y: point.y / size.height)
    }

    /// 左上原点归一化 box → 视图坐标 box。
    static func viewBox(from normalized: CGRect, in size: CGSize) -> CGRect {
        CGRect(
            x: normalized.minX * size.width,
            y: normalized.minY * size.height,
            width: normalized.width * size.width,
            height: normalized.height * size.height
        )
    }

    /// 归一化像素坐标 → mask 像素坐标（按 mask 尺寸缩放）。
    static func maskPixel(normalized: CGPoint, maskWidth: Int, maskHeight: Int) -> (x: Int, y: Int) {
        let x = min(maskWidth - 1, max(0, Int(normalized.x * CGFloat(maskWidth))))
        let y = min(maskHeight - 1, max(0, Int(normalized.y * CGFloat(maskHeight))))
        return (x, y)
    }

    /// 归一化像素坐标 → 深度图像素坐标。
    static func depthPixel(normalized: CGPoint, depthWidth: Int, depthHeight: Int) -> (x: Int, y: Int) {
        let x = min(depthWidth - 1, max(0, Int(normalized.x * CGFloat(depthWidth))))
        let y = min(depthHeight - 1, max(0, Int(normalized.y * CGFloat(depthHeight))))
        return (x, y)
    }
}
