import CoreGraphics
import Foundation

/// 统一坐标转换（任务书第 37 条）。
///
/// 坐标系约定：
/// - **模型空间**（YOLO 输出，scaleFill 预处理）：归一化，左下原点。
///   因为 .scaleFill 是纯缩放，模型归一化坐标 ==「显示方向图像」归一化坐标（仅原点不同）。
/// - **显示空间**：竖屏方向图像归一化，左上原点（ny 向下）。
/// - **相机像素空间**：capturedImage 像素（横向，左上原点，orientation .right 旋转关系）。
/// - **深度像素空间**：depthMap 像素（与相机像素同方向）。
/// - **mask 像素空间**：YOLO mask（160x160），左上原点，与显示空间归一化直接对应。
/// - **视图空间**：ARView 坐标（点）。
///
/// orientation .right（顺时针 90°）换算：
///   显示 (nx, ny) → 相机像素：px = ny * W, py = H * (1 - nx)
enum CoordinateMapper {
    // MARK: - 原点翻转

    /// 模型空间（左下原点）→ 显示空间（左上原点）。
    static func displaySpace(bottomLeft box: CGRect) -> CGRect {
        CGRect(x: box.minX, y: 1 - box.maxY, width: box.width, height: box.height)
    }

    /// 显示空间（左上原点）→ 模型空间（左下原点）。
    static func bottomLeft(display box: CGRect) -> CGRect {
        CGRect(x: box.minX, y: 1 - box.maxY, width: box.width, height: box.height)
    }

    // MARK: - 显示空间 → 像素空间

    /// 显示归一化点 → 相机像素。
    static func cameraPixel(normalized: CGPoint, cameraSize: CGSize) -> (x: Int, y: Int) {
        let width = Int(cameraSize.width)
        let height = Int(cameraSize.height)
        let px = min(width - 1, max(0, Int(normalized.y * cameraSize.width)))
        let py = min(height - 1, max(0, Int(cameraSize.height * (1 - normalized.x))))
        return (px, py)
    }

    /// 显示归一化点 → 深度图像素。
    static func depthPixel(normalized: CGPoint, depthSize: CGSize) -> (x: Int, y: Int) {
        let width = Int(depthSize.width)
        let height = Int(depthSize.height)
        let px = min(width - 1, max(0, Int(normalized.y * depthSize.width)))
        let py = min(height - 1, max(0, Int(depthSize.height * (1 - normalized.x))))
        return (px, py)
    }

    /// 显示归一化点 → mask 像素（mask 与显示空间直接对应，左上原点）。
    static func maskPixel(normalized: CGPoint, maskWidth: Int, maskHeight: Int) -> (x: Int, y: Int) {
        let x = min(maskWidth - 1, max(0, Int(normalized.x * CGFloat(maskWidth))))
        let y = min(maskHeight - 1, max(0, Int(normalized.y * CGFloat(maskHeight))))
        return (x, y)
    }

    /// 相机像素 → 显示归一化点。
    static func displayNormalized(cameraPixel px: Int, py: Int, cameraSize: CGSize) -> CGPoint {
        guard cameraSize.width > 0, cameraSize.height > 0 else { return .zero }
        return CGPoint(
            x: 1 - CGFloat(py) / cameraSize.height,
            y: CGFloat(px) / cameraSize.width
        )
    }

    // MARK: - 视图空间

    /// 模型空间框（左下原点归一化）→ 视图框（displayTransform 映射四角）。
    static func viewBox(bottomLeft box: CGRect, transform: CGAffineTransform) -> CGRect {
        let corners = [
            CGPoint(x: box.minX, y: box.minY),
            CGPoint(x: box.maxX, y: box.minY),
            CGPoint(x: box.minX, y: box.maxY),
            CGPoint(x: box.maxX, y: box.maxY)
        ].map { $0.applying(transform) }
        let xs = corners.map(\.x)
        let ys = corners.map(\.y)
        let minX = xs.min() ?? 0
        let maxX = xs.max() ?? 0
        let minY = ys.min() ?? 0
        let maxY = ys.max() ?? 0
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// 视图点 → 模型空间归一化点（左下原点）。
    static func bottomLeftNormalized(viewPoint: CGPoint, transform: CGAffineTransform) -> CGPoint {
        let normalized = viewPoint.applying(transform.inverted())
        return normalized
    }

    /// 视图点 → 显示空间归一化点（左上原点）。
    static func displayNormalized(viewPoint: CGPoint, transform: CGAffineTransform) -> CGPoint {
        let bottomLeft = bottomLeftNormalized(viewPoint: viewPoint, transform: transform)
        return CGPoint(x: bottomLeft.x, y: 1 - bottomLeft.y)
    }
}
