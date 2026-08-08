import Foundation
import RealityKit
import simd
import UIKit

/// RealityKit 渲染：测量线、点位球、OBB 包围盒。全部使用世界坐标实体。
@MainActor
final class ARRenderer {
    weak var arView: ARView?
    private var anchor: AnchorEntity?
    private var lineEntities: [ModelEntity] = []
    private var sphereEntities: [ModelEntity] = []

    func attach(to view: ARView) {
        arView = view
        guard anchor == nil else { return }
        let root = AnchorEntity(world: .zero)
        view.scene.addAnchor(root)
        anchor = root
        AppLog.ar.info("Renderer attached")
    }

    func showLine(from start: SIMD3<Float>, to end: SIMD3<Float>, color: UIColor = .cyan) {
        guard let anchor else { return }
        clearAll()
        let material = SimpleMaterial(color: color, isMetallic: false)
        let line = ModelEntity(mesh: .generateLine(from: start, to: end, radius: 0.004), materials: [material])
        let startSphere = sphere(at: start, radius: 0.012, material: material)
        let endSphere = sphere(at: end, radius: 0.012, material: material)
        anchor.addChild(line)
        anchor.addChild(startSphere)
        anchor.addChild(endSphere)
        lineEntities = [line]
        sphereEntities = [startSphere, endSphere]
    }

    func showPoints(_ points: [SIMD3<Float>], lines: [(SIMD3<Float>, SIMD3<Float>)] = []) {
        guard let anchor else { return }
        clearAll()
        let material = SimpleMaterial(color: .orange, isMetallic: false)
        for point in points {
            let entity = sphere(at: point, radius: 0.01, material: material)
            anchor.addChild(entity)
            sphereEntities.append(entity)
        }
        for (start, end) in lines {
            let entity = ModelEntity(mesh: .generateLine(from: start, to: end, radius: 0.003), materials: [material])
            anchor.addChild(entity)
            lineEntities.append(entity)
        }
    }

    func showBoundingBox(_ box: OrientedBoundingBox, color: UIColor = .green) {
        guard let anchor else { return }
        clearAll()
        let material = SimpleMaterial(color: color, isMetallic: false)
        let edges: [(Int, Int)] = [
            (0, 1), (1, 3), (3, 2), (2, 0),
            (4, 5), (5, 7), (7, 6), (6, 4),
            (0, 4), (1, 5), (2, 6), (3, 7)
        ]
        for (a, b) in edges {
            let entity = ModelEntity(mesh: .generateLine(from: box.corners[a], to: box.corners[b], radius: 0.004), materials: [material])
            anchor.addChild(entity)
            lineEntities.append(entity)
        }
        for corner in box.corners {
            let entity = sphere(at: corner, radius: 0.008, material: material)
            anchor.addChild(entity)
            sphereEntities.append(entity)
        }
    }

    func clearAll() {
        guard let anchor else { return }
        for entity in lineEntities + sphereEntities {
            entity.removeFromParent()
        }
        lineEntities.removeAll()
        sphereEntities.removeAll()
    }

    private func sphere(at position: SIMD3<Float>, radius: Float, material: SimpleMaterial) -> ModelEntity {
        let entity = ModelEntity(mesh: .generateSphere(radius: radius), materials: [material])
        entity.position = position
        return entity
    }
}
