import ARKit
import CoreVideo
import Foundation
import Vision

/// 后台推理服务：YOLO 检测 + 目标实例分割。
///
/// - actor 隔离，推理不阻塞主线程
/// - 节流：约 5~8 FPS
/// - 防堆积：上一帧未完成时跳过新帧
/// - 输入 CVPixelBuffer 直接给 VNImageRequestHandler，禁止 UIImage 中转
actor VisionInferenceService {
    private let detector: ObjectDetector?
    private let interval: TimeInterval
    private var isBusy = false
    private var lastRunTime: TimeInterval = 0

    var isAvailable: Bool { detector != nil }

    init(interval: TimeInterval = 0.15) {
        self.interval = interval
        self.detector = ObjectDetector()
    }

    /// 返回 nil 表示跳过（节流或堆积）；返回空数组表示检测完成但无目标。
    func detect(pixelBuffer: CVPixelBuffer, threshold: Float) async -> [DetectedObject]? {
        guard let detector else { return [] }
        guard !isBusy else { return nil }
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastRunTime >= interval else { return nil }
        isBusy = true
        defer { isBusy = false }
        lastRunTime = now

        let start = Date()
        do {
            let objects = try detector.detect(
                pixelBuffer: pixelBuffer,
                orientation: .right,
                threshold: threshold
            )
            let elapsed = Int(Date().timeIntervalSince(start) * 1000)
            if !objects.isEmpty {
                AppLog.vision.info("objects=\(objects.count) inference=\(elapsed)ms")
            }
            return objects
        } catch {
            AppLog.vision.error("Detection failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// 为目标检测框分割对应实例。返回 nil 表示该帧跳过；无匹配实例返回 nil。
    func segmentInstance(
        pixelBuffer: CVPixelBuffer,
        targetBox: CGRect,
        minimumIoU: Float
    ) async -> ObjectSegmenter.SegmentResult? {
        guard !isBusy else { return nil }
        let start = Date()
        do {
            let result = try ObjectSegmenter.segmentInstance(
                pixelBuffer: pixelBuffer,
                orientation: .right,
                targetBox: targetBox,
                minimumIoU: minimumIoU
            )
            if let result {
                let elapsed = Int(Date().timeIntervalSince(start) * 1000)
                AppLog.vision.info(
                    "segmented instance IoU=\(String(format: "%.2f", result.matchedIoU)) elapsed=\(elapsed)ms"
                )
            }
            return result
        } catch {
            AppLog.vision.error("Segmentation failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    func allForegroundMask(pixelBuffer: CVPixelBuffer) async -> CVPixelBuffer? {
        guard !isBusy else { return nil }
        do {
            return try ObjectSegmenter.allForegroundMask(pixelBuffer: pixelBuffer, orientation: .right)
        } catch {
            AppLog.vision.error("Foreground mask failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}
