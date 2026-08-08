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

    func testPCA2DFindsPrincipalAxis() {
        var points: [SIMD2<Float>] = []
        for index in 0..<100 {
            points.append(SIMD2(Float(index % 20) * 0.01, Float(index / 20) * 0.001))
        }
        let pca = PCA2D.principalAxes(of: points)
        XCTAssertNotNil(pca)
        XCTAssertGreaterThan(abs(pca?.primary.x ?? 0), 0.9, "principal axis should be near x")
        let primaryVariance = pca?.primaryVariance ?? 0
        let secondaryVariance = pca?.secondaryVariance ?? 1
        XCTAssertGreaterThan(primaryVariance, secondaryVariance)
    }

    func testGravityAlignedOBBRecoversRotatedCuboid() {
        let dims = SIMD3<Float>(0.4, 0.8, 0.2)
        let rotation = simd_float3x3(simd_quatf(angle: .pi / 4, axis: SIMD3(0, 1, 0)))
        var points: [SIMD3<Float>] = []
        let half = dims * 0.5
        for y in [-1, 1] as [Float] {
            for x in [-1, 1] as [Float] {
                for z in [-1, 1] as [Float] {
                    points.append(rotation * (SIMD3(x, y, z) * half))
                }
            }
        }
        let obb = GravityAlignedOBB.compute(of: points)
        XCTAssertNotNil(obb)
        XCTAssertEqual(obb?.dimensions.height ?? 0, 0.8, accuracy: 0.01)
        let horizontal = sortedPair(obb?.dimensions.width ?? 0, obb?.dimensions.depth ?? 0)
        XCTAssertEqual(horizontal[0], 0.2, accuracy: 0.01)
        XCTAssertEqual(horizontal[1], 0.4, accuracy: 0.01)
    }

    func testGravityAlignedOBBTrimsOutliers() {
        var points: [SIMD3<Float>] = []
        let half = SIMD3<Float>(0.15, 0.25, 0.35)
        for corner in [
            SIMD3<Float>(-1, -1, -1), SIMD3(1, -1, -1), SIMD3(-1, 1, -1), SIMD3(1, 1, -1),
            SIMD3(-1, -1, 1), SIMD3(1, -1, 1), SIMD3(-1, 1, 1), SIMD3(1, 1, 1)
        ] {
            for _ in 0..<25 {
                points.append(SIMD3(
                    corner.x * half.x + .random(in: -0.004...0.004),
                    corner.y * half.y + .random(in: -0.004...0.004),
                    corner.z * half.z + .random(in: -0.004...0.004)
                ))
            }
        }
        points.append(SIMD3(10, 10, 10))
        points.append(SIMD3(-8, -9, -7))

        let obb = GravityAlignedOBB.compute(of: points)
        XCTAssertNotNil(obb)
        XCTAssertEqual(obb?.dimensions.height ?? 0, 0.5, accuracy: 0.02)
        let horizontal = sortedPair(obb?.dimensions.width ?? 0, obb?.dimensions.depth ?? 0)
        XCTAssertEqual(horizontal[0], 0.3, accuracy: 0.02)
        XCTAssertEqual(horizontal[1], 0.7, accuracy: 0.02)
    }

    func testOutlierFilterRemovesFarPoint() {
        var points: [SIMD3<Float>] = []
        for index in 0..<20 {
            points.append(SIMD3(Float(index % 4) * 0.01, Float(index / 4) * 0.01, 1))
        }
        points.append(SIMD3(10, 10, 10))
        let filtered = BoundingBox3D.filterOutliers(points)
        XCTAssertEqual(filtered.count, 20)
    }

    private func sortedPair(_ a: Float, _ b: Float) -> [Float] {
        [min(a, b), max(a, b)]
    }
}
