import Foundation
import Photos
import UIKit

enum ScreenshotError: LocalizedError {
    case photoDenied

    var errorDescription: String? {
        switch self {
        case .photoDenied: return "没有照片库权限"
        }
    }
}

enum ScreenshotService {
    /// 捕获当前主窗口画面（含 AR 与 SwiftUI 覆盖层）。
    static func captureWindow() -> UIImage? {
        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap({ $0.windows })
            .first(where: { $0.isKeyWindow }) else { return nil }
        let renderer = UIGraphicsImageRenderer(bounds: window.bounds)
        return renderer.image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
    }

    static func saveToPhotos(_ image: UIImage) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            throw ScreenshotError.photoDenied
        }
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.creationRequestForAsset(from: image)
        }
        AppLog.measure.info("Screenshot saved to photo library")
    }

    /// 保存到 Documents，返回文件名。
    static func saveToDocuments(_ image: UIImage) -> String? {
        guard let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first,
              let data = image.pngData() else { return nil }
        let name = "measure-\(UUID().uuidString.prefix(8)).png"
        do {
            let url = directory.appendingPathComponent(name)
            try data.write(to: url, options: .atomic)
            return url.lastPathComponent
        } catch {
            AppLog.measure.error("Screenshot save to documents failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}
