import CoreGraphics
import Foundation

/// 跨帧目标关联（第一版不做 DeepSORT）：
/// IoU + 类别 + 中心距离 组合距离，保持 stableTargetID。
struct ObjectTracker {
    private var lastTracked: DetectedObject?

    /// 返回当前帧最可能延续的目标（保持上一帧的 id 以维持稳定 ID）。
    mutating func track(_ detections: [DetectedObject]) -> DetectedObject? {
        guard let last = lastTracked else {
            lastTracked = detections.first
            return lastTracked
        }
        guard !detections.isEmpty else {
            lastTracked = nil
            return nil
        }
        let candidate = detections.min { a, b in
            associationCost(a, to: last) < associationCost(b, to: last)
        }
        if let candidate, associationCost(candidate, to: last) < 0.5 {
            var updated = candidate
            updated.id = last.id
            lastTracked = updated
            return updated
        }
        // 上一目标丢失，重新开始跟踪首个候选。
        lastTracked = detections.first
        return lastTracked
    }

    private func associationCost(_ a: DetectedObject, to b: DetectedObject) -> Float {
        let iou = BoxOps.intersectionOverUnion(a.boundingBox, b.boundingBox)
        let centerDistance = hypotf(Float(a.center.x - b.center.x), Float(a.center.y - b.center.y))
        let labelCost: Float = a.label == b.label ? 0 : 0.25
        return (1 - iou) + centerDistance * 0.5 + labelCost
    }
}
