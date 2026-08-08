import XCTest
@testable import LiDARMeasure

final class MappingTests: XCTestCase {
    func testDisplaySpaceRoundTrip() {
        let box = CGRect(x: 0.2, y: 0.3, width: 0.4, height: 0.5)
        let display = CoordinateMapper.displaySpace(bottomLeft: box)
        XCTAssertEqual(display.minY, 0.2, accuracy: 0.0001)
        XCTAssertEqual(display.height, 0.5, accuracy: 0.0001)
        let back = CoordinateMapper.bottomLeft(display: display)
        XCTAssertEqual(back.minX, box.minX, accuracy: 0.0001)
        XCTAssertEqual(back.minY, box.minY, accuracy: 0.0001)
    }

    func testCameraPixelPortraitOrientation() {
        // orientation .right（顺时针 90°）：显示左上 → 相机像素 (0, H-1)。
        let size = CGSize(width: 1920, height: 1440)
        let topLeft = CoordinateMapper.cameraPixel(normalized: .zero, cameraSize: size)
        XCTAssertEqual(topLeft.x, 0)
        XCTAssertEqual(topLeft.y, 1439)
        // 显示右下 (1,1) → 相机像素 (W-1, 0)。
        let bottomRight = CoordinateMapper.cameraPixel(normalized: CGPoint(x: 1, y: 1), cameraSize: size)
        XCTAssertEqual(bottomRight.x, 1919)
        XCTAssertEqual(bottomRight.y, 0)
    }

    func testCameraDisplayRoundTrip() {
        let size = CGSize(width: 1920, height: 1440)
        let original = CGPoint(x: 0.37, y: 0.61)
        let pixel = CoordinateMapper.cameraPixel(normalized: original, cameraSize: size)
        let back = CoordinateMapper.displayNormalized(cameraPixel: pixel.x, py: pixel.y, cameraSize: size)
        XCTAssertEqual(back.x, original.x, accuracy: 0.01)
        XCTAssertEqual(back.y, original.y, accuracy: 0.01)
    }

    func testDepthPixelUsesDepthSize() {
        let size = CGSize(width: 256, height: 192)
        let center = CoordinateMapper.depthPixel(normalized: CGPoint(x: 0.5, y: 0.5), depthSize: size)
        XCTAssertEqual(center.x, 128)
        XCTAssertEqual(center.y, 96)
        let topLeft = CoordinateMapper.depthPixel(normalized: .zero, depthSize: size)
        XCTAssertEqual(topLeft.y, 191, "display top-left maps to bottom row of landscape depth map")
    }

    func testMaskPixel() {
        let p = CoordinateMapper.maskPixel(normalized: CGPoint(x: 0.5, y: 0.5), maskWidth: 160, maskHeight: 160)
        XCTAssertEqual(p.x, 80)
        XCTAssertEqual(p.y, 80)
    }

    func testViewBoxWithIdentityTransform() {
        let box = CGRect(x: 0.2, y: 0.3, width: 0.4, height: 0.5)
        let viewBox = CoordinateMapper.viewBox(bottomLeft: box, transform: .identity)
        XCTAssertEqual(viewBox.minX, 0.2, accuracy: 0.0001)
        XCTAssertEqual(viewBox.minY, 0.3, accuracy: 0.0001)
        XCTAssertEqual(viewBox.width, 0.4, accuracy: 0.0001)
    }

    func testDisplayNormalizedFromViewPoint() {
        let transform = CGAffineTransform(scaleX: 400, y: 800)
        let p = CoordinateMapper.displayNormalized(viewPoint: CGPoint(x: 100, y: 400), transform: transform)
        XCTAssertEqual(p.x, 0.25, accuracy: 0.0001)
        XCTAssertEqual(p.y, 0.5, accuracy: 0.0001)
    }

    func testBottomLeftNormalizedFromViewPoint() {
        let transform = CGAffineTransform(scaleX: 400, y: 800)
        let p = CoordinateMapper.bottomLeftNormalized(viewPoint: CGPoint(x: 100, y: 400), transform: transform)
        XCTAssertEqual(p.x, 0.25, accuracy: 0.0001)
        XCTAssertEqual(p.y, 0.5, accuracy: 0.0001)
    }
}
