import CoreGraphics
import Foundation
import CoreML

/// YOLOv8 输出解码与 NMS（模型为 raw 输出，不含 NMS，这里使用成熟标准实现）。
///
/// 模型输出形状 [1, 84, 8400]（channels-first）：
/// - 前 4 通道：xywh（相对模型输入 640x640 的归一化中心坐标与尺寸）
/// - 后 80 通道：COCO 类别分数（YOLOv8 无独立 objectness，类别分数即置信度）
enum YOLODecoder {
    static let classCount = 80

    static func decode(
        _ array: MLMultiArray,
        threshold: Float,
        iouThreshold: Float = 0.45
    ) -> [DetectedObject] {
        guard array.shape.count >= 2 else { return [] }
        let anchorCount = Int(array.shape[2])
        let channelCount = Int(array.shape[1])
        guard anchorCount > 0, channelCount >= classCount + 4 else { return [] }

        let pointer = array.dataPointer.bindMemory(to: Float.self, capacity: anchorCount * channelCount)
        let stride = anchorCount

        var candidates: [DetectedObject] = []
        candidates.reserveCapacity(64)

        for anchor in 0..<anchorCount {
            let cx = pointer[anchor + stride * 0]
            let cy = pointer[anchor + stride * 1]
            let width = pointer[anchor + stride * 2]
            let height = pointer[anchor + stride * 3]
            guard cx.isFinite, cy.isFinite, width.isFinite, height.isFinite,
                  width > 0, height > 0 else { continue }

            var bestClass = 0
            var bestScore: Float = -1
            for classIndex in 4..<channelCount {
                let score = pointer[anchor + stride * classIndex]
                if score > bestScore {
                    bestScore = score
                    bestClass = classIndex
                }
            }
            guard bestScore >= threshold else { continue }

            var x1 = cx - width / 2
            var y1 = cy - height / 2
            var w = width
            var h = height
            if x1 < 0 { w += x1; x1 = 0 }
            if y1 < 0 { h += y1; y1 = 0 }
            w = min(w, 1 - x1)
            h = min(h, 1 - y1)
            guard w > 0, h > 0 else { continue }

            candidates.append(DetectedObject(
                id: UUID(),
                label: COCOClassNames.name(for: bestClass),
                confidence: bestScore,
                boundingBox: CGRect(x: CGFloat(x1), y: CGFloat(y1), width: CGFloat(w), height: CGFloat(h))
            ))
        }

        return nonMaximumSuppression(candidates, iouThreshold: iouThreshold)
    }

    /// 标准贪心 NMS：按置信度降序保留，抑制与已选框 IoU 超过阈值的候选。
    static func nonMaximumSuppression(
        _ candidates: [DetectedObject],
        iouThreshold: Float
    ) -> [DetectedObject] {
        var remaining = candidates.sorted { $0.confidence > $1.confidence }
        var kept: [DetectedObject] = []
        while let best = remaining.first {
            kept.append(best)
            remaining.removeFirst()
            remaining = remaining.filter {
                BoxOps.intersectionOverUnion($0.boundingBox, best.boundingBox) <= iouThreshold
            }
        }
        return kept
    }
}
