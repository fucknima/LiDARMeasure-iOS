import CoreGraphics
import CoreVideo
import Foundation
import Vision

/// 前景实例分割（iOS 17+ 系统内置，无模型体积）。
enum ObjectSegmenter {
    static func mask(
        pixelBuffer: CVPixelBuffer,
        orientation: CGImagePropertyOrientation = .right
    ) throws -> CVPixelBuffer? {
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: orientation)
        try handler.perform([request])
        guard let observation = request.results?.first else { return nil }
        return try observation.generateScaledMaskForImage(forInstances: observation.allInstances, from: handler)
    }
}
