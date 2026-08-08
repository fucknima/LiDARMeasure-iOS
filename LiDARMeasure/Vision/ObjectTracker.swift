import CoreGraphics
import Foundation

/// 跟踪目标：持有跨帧稳定的 stableID（任务书第 45~49 条）。
struct TrackedObject: Identifiable {
    let stableID: UUID
    var object: SegmentedObject
    var missedFrames: Int = 0

    var id: UUID { stableID }
}

/// 跨帧目标跟踪：label + IoU + center distance 贪婪关联。
///
/// - 输出 TrackedObject(stableID)，UI 与测量必须使用 stableID
/// - 允许短暂丢失 missedFrames <= maxMissed，超过后删除 track
/// - 用户选择基于 stableID；只要目标还在，禁止自动换目标
struct ObjectTracker {
    private var tracks: [UUID: TrackedObject] = [:]

    /// 用本帧检测更新跟踪，返回当前全部有效 tracks。
    mutating func update(
        detections: [SegmentedObject],
        maxMissed: Int = 3
    ) -> [TrackedObject] {
        var available = detections
        var updated: [TrackedObject] = []

        for (stableID, track) in tracks {
            guard let matchIndex = available.indices.min(by: {
                associationCost(available[$0], to: track.object) < associationCost(available[$1], to: track.object)
            }), associationCost(available[matchIndex], to: track.object) < 0.5 else {
                var stale = track
                stale.missedFrames += 1
                if stale.missedFrames <= maxMissed {
                    updated.append(stale)
                }
                continue
            }
            var fresh = track
            fresh.object = available.remove(at: matchIndex)
            fresh.object.stableID = stableID
            fresh.missedFrames = 0
            updated.append(fresh)
        }

        // 新目标建立 track。
        for detection in available {
            var object = detection
            object.stableID = UUID()
            updated.append(TrackedObject(stableID: object.stableID, object: object))
        }

        tracks = Dictionary(uniqueKeysWithValues: updated.map { ($0.stableID, $0) })
        return updated
    }

    func trackedObject(stableID: UUID) -> TrackedObject? {
        tracks[stableID]
    }

    mutating func clear() {
        tracks.removeAll()
    }

    private func associationCost(_ a: SegmentedObject, to b: SegmentedObject) -> Float {
        let iou = BoxOps.intersectionOverUnion(a.boundingBox, b.boundingBox)
        let centerDistance = hypotf(
            Float(a.center.x - b.center.x),
            Float(a.center.y - b.center.y)
        )
        let labelCost: Float = a.label == b.label ? 0 : 0.25
        return (1 - iou) + centerDistance * 0.5 + labelCost
    }
}
