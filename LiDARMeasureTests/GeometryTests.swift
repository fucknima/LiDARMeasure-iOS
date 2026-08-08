import XCTest
import simd
@testable import LiDARMeasure

final class GeometryTests: XCTestCase {
    func testDistanceUsesMeters() {
        let a = SIMD3<Float>(0, 0, 0)
        let b = SIMD3<Float>(0.3, 0.4, 0)
        XCTAssertEqual(BoundingBox3D.distance(a, b), 0.5, accuracy: 0.0001)
    }

    func testAxisAlignedDimensions() {
        let points: [SIMD3<Float>] = [
            SIMD3(-0.2, 0.1, -0.4), SIMD3(0.2, 0.6, 0.4)
        ]
        let dimensions = BoundingBox3D.axisAlignedDimensions(of: points)
        XCTAssertEqual(dimensions?.width ?? 0, 0.4, accuracy: 0.0001)
        XCTAssertEqual(dimensions?.height ?? 0, 0.5, accuracy: 0.0001)
        XCTAssertEqual(dimensions?.depth ?? 0, 0.8, accuracy: 0.0001)
    }

    func testOrientedBoundingBoxRecoversRotatedCuboid() {
        let dims = SIMD3<Float>(0.4, 0.8, 0.2)
        let rotation = simd_float3x3(simd_quatf(angle: .pi / 4, axis: SIMD3(0, 1, 0)))
        let points = BoundingBox3D.cornerPoints(
            center: .zero,
            axes: rotation,
            dimensions: MeasurementDimensions(width: dims.x, height: dims.y, depth: dims.z)
        )

        let box = BoundingBox3D.orientedBoundingBox(of: points)
        XCTAssertNotNil(box)
        // 重力轴固定为高度；水平两轴因 PCA 对称性可能互换宽度/深度，
        // 断言使用标签不变量（高度精确 + 水平方向尺寸集合一致）。
        XCTAssertEqual(box?.dimensions.height ?? 0, 0.8, accuracy: 0.01)
        let horizontal = sortedPair(box?.dimensions.width ?? 0, box?.dimensions.depth ?? 0)
        let expected = sortedPair(0.4, 0.2)
        XCTAssertEqual(horizontal[0], expected[0], accuracy: 0.01)
        XCTAssertEqual(horizontal[1], expected[1], accuracy: 0.01)
    }

    func testOrientedBoundingBoxAxisAligned() {
        let points = BoundingBox3D.cornerPoints(
            center: SIMD3(1, 2, 3),
            axes: matrix_identity_float3x3,
            dimensions: MeasurementDimensions(width: 0.3, height: 0.5, depth: 0.7)
        )
        let box = BoundingBox3D.orientedBoundingBox(of: points)
        XCTAssertNotNil(box)
        XCTAssertEqual(box?.dimensions.height ?? 0, 0.5, accuracy: 0.0001)
        let horizontal = sortedPair(box?.dimensions.width ?? 0, box?.dimensions.depth ?? 0)
        let expected = sortedPair(0.3, 0.7)
        XCTAssertEqual(horizontal[0], expected[0], accuracy: 0.0001)
        XCTAssertEqual(horizontal[1], expected[1], accuracy: 0.0001)
        XCTAssertEqual(box?.center.x ?? 0, 1, accuracy: 0.0001)
        XCTAssertEqual(box?.center.y ?? 0, 2, accuracy: 0.0001)
        XCTAssertEqual(box?.center.z ?? 0, 3, accuracy: 0.0001)
    }

    private func sortedPair(_ a: Float, _ b: Float) -> [Float] {
        [min(a, b), max(a, b)]
    }

    func testOutlierFilterRemovesFarPoint() {
        var points = (0..<20).map { index in
            Point3D(value: SIMD3<Float>(Float(index % 4) * 0.01, Float(index / 4) * 0.01, 1), confidence: 1)
        }
        points.append(Point3D(value: SIMD3<Float>(10, 10, 10), confidence: 1))
        let filtered = BoundingBox3D.filterOutliers(points)
        XCTAssertEqual(filtered.count, 20)
    }
}
