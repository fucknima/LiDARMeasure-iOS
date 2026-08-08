import ARKit
import CoreVideo
import Foundation
import Vision

struct VisionPipelineResult {
    let observation: VisionObservation?
    let foregroundMask: CVPixelBuffer?
}

/// 节流的 Vision 流水线：检测 + 可选前景分割。
final class VisionPipeline {
    private let detector = ObjectDetector()
    private var lastRunTime: TimeInterval = 0
    let interval: TimeInterval

    init(interval: TimeInterval = 0.2) {
        self.interval = interval
    }

    func analyze(
        frame: ARFrame,
        now: TimeInterval = ProcessInfo.processInfo.systemUptime
    ) -> VisionPipelineResult? {
        guard now - lastRunTime >= interval else { return nil }
        lastRunTime = now
        let start = Date()
        do {
            let observation = try detector.detect(pixelBuffer: frame.capturedImage)
            var mask: CVPixelBuffer?
            if #available(iOS 17.0, *),
               let box = observation?.boundingBox,
               box.width > 0.15, box.height > 0.15 {
                mask = try? ObjectSegmenter.mask(pixelBuffer: frame.capturedImage)
            }
            let elapsed = String(format: "%.2f", Date().timeIntervalSince(start))
            AppLog.vision.info(
                "Vision analyzed in \(elapsed)s, found=\(observation?.identifier ?? "none")"
            )
            return VisionPipelineResult(observation: observation, foregroundMask: mask)
        } catch {
            AppLog.vision.error("Vision analysis failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}
