import CoreGraphics
import Foundation
import UIKit

/// 方向映射：设备/界面方向 → Vision 图像方向。
/// 本 App 锁定竖屏，默认 .right；该映射供后续横屏等场景复用。
enum CameraOrientationMapper {
    static func orientation(for interface: UIInterfaceOrientation) -> CGImagePropertyOrientation {
        switch interface {
        case .landscapeLeft: return .up
        case .landscapeRight: return .down
        case .portraitUpsideDown: return .left
        default: return .right
        }
    }

    static func orientation(for device: UIDeviceOrientation) -> CGImagePropertyOrientation {
        switch device {
        case .landscapeLeft: return .up
        case .landscapeRight: return .down
        case .portraitUpsideDown: return .left
        default: return .right
        }
    }
}
