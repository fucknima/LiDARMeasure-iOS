import CoreGraphics
import Foundation

/// 矩形几何工具：IoU、面积等。
enum BoxOps {
    static func intersectionOverUnion(_ a: CGRect, _ b: CGRect) -> Float {
        let intersection = a.intersection(b)
        guard !intersection.isNull else { return 0 }
        let areaA = a.width * a.height
        let areaB = b.width * b.height
        let areaI = intersection.width * intersection.height
        let union = areaA + areaB - areaI
        guard union > 0 else { return 0 }
        return Float(areaI / union)
    }

    static func area(_ box: CGRect) -> CGFloat {
        box.width * box.height
    }
}
