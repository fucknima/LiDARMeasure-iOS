import ARKit
import CoreVideo
import Foundation
import simd

/// 从深度图构建世界坐标点云：ROI / 前景掩码 / 深度带 / 置信度过滤。
enum PointCloudBuilder {
    struct Configuration {
        var stride: Int = 4
        var minimumConfidence: Float = 0.5
        var depthBand: ClosedRange<Float>?
        var roi: CGRect?
        var foregroundMask: CVPixelBuffer?
    }

    static func build(from frame: ARFrame, configuration: Configuration) -> [Point3D] {
        guard let depthData = DepthReader.bestDepthData(from: frame) else { return [] }
        let map = depthData.depthMap
        let width = CVPixelBufferGetWidth(map)
        let height = CVPixelBufferGetHeight(map)
        guard width > 0, height > 0 else { return [] }

        let cameraImageWidth = Float(CVPixelBufferGetWidth(frame.capturedImage))
        let cameraImageHeight = Float(CVPixelBufferGetHeight(frame.capturedImage))
        let intrinsics = frame.camera.intrinsics
        let cameraTransform = frame.camera.transform
        let scaleX = cameraImageWidth / Float(width)
        let scaleY = cameraImageHeight / Float(height)

        CVPixelBufferLockBaseAddress(map, .readOnly)
        let confidenceMap = depthData.confidenceMap
        let foregroundMask = configuration.foregroundMask
        if let confidenceMap {
            CVPixelBufferLockBaseAddress(confidenceMap, .readOnly)
        }
        if let foregroundMask {
            CVPixelBufferLockBaseAddress(foregroundMask, .readOnly)
        }
        defer {
            CVPixelBufferUnlockBaseAddress(map, .readOnly)
            if let confidenceMap {
                CVPixelBufferUnlockBaseAddress(confidenceMap, .readOnly)
            }
            if let foregroundMask {
                CVPixelBufferUnlockBaseAddress(foregroundMask, .readOnly)
            }
        }
        guard let base = CVPixelBufferGetBaseAddress(map) else { return [] }
        let rowStride = CVPixelBufferGetBytesPerRow(map) / MemoryLayout<Float32>.stride
        let values = base.assumingMemoryBound(to: Float32.self)

        let confidenceValues = confidenceMap
            .flatMap { CVPixelBufferGetBaseAddress($0) }
            .map { $0.assumingMemoryBound(to: UInt8.self) }
        let confidenceStride = confidenceMap.map { CVPixelBufferGetBytesPerRow($0) } ?? 0

        let maskValues = foregroundMask
            .flatMap { CVPixelBufferGetBaseAddress($0) }
            .map { $0.assumingMemoryBound(to: UInt8.self) }
        let maskWidth = foregroundMask.map { CVPixelBufferGetWidth($0) } ?? 0
        let maskHeight = foregroundMask.map { CVPixelBufferGetHeight($0) } ?? 0
        let maskStride = foregroundMask.map { CVPixelBufferGetBytesPerRow($0) } ?? 0

        let stride = max(1, configuration.stride)
        var points: [Point3D] = []
        points.reserveCapacity((width / stride) * (height / stride))

        for y in stride / 2..<height where y % stride == stride / 2 {
            for x in stride / 2..<width where x % stride == stride / 2 {
                if let roi = configuration.roi {
                    let normalized = CGPoint(x: CGFloat(x) / CGFloat(width), y: CGFloat(y) / CGFloat(height))
                    guard roi.contains(normalized) else { continue }
                }
                if let maskValues, maskWidth > 0, maskHeight > 0 {
                    let mx = min(maskWidth - 1, x * maskWidth / width)
                    let my = min(maskHeight - 1, y * maskHeight / height)
                    guard maskValues[my * maskStride + mx] > 0 else { continue }
                }
                let depth = values[y * rowStride + x]
                guard depth.isFinite, depth > 0 else { continue }
                if let band = configuration.depthBand, !band.contains(depth) { continue }

                let confidence: Float
                if let confidenceValues {
                    confidence = Float(confidenceValues[y * confidenceStride + x]) / 2
                } else {
                    confidence = 1
                }
                guard confidence >= configuration.minimumConfidence else { continue }

                let cameraPoint = SIMD3<Float>(
                    (Float(x) * scaleX - intrinsics.columns.2.x) / intrinsics.columns.0.x,
                    (Float(y) * scaleY - intrinsics.columns.2.y) / intrinsics.columns.1.y,
                    1
                ) * depth
                let world = cameraTransform * SIMD4(cameraPoint, 1)
                points.append(Point3D(
                    value: SIMD3(world.x, world.y, world.z),
                    confidence: confidence
                ))
            }
        }
        return points
    }
}
