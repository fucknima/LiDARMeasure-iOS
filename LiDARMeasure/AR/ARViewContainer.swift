import RealityKit
import SwiftUI
import UIKit

struct ARViewContainer: UIViewRepresentable {
    let viewModel: MeasureViewModel

    func makeUIView(context: Context) -> ARView {
        let view = ARView(frame: .zero, cameraMode: .ar, automaticallyConfigureSession: false)
        view.contentMode = .scaleAspectFill
        viewModel.sessionManager.attach(to: view)
        viewModel.renderer.attach(to: view)
        viewModel.sessionManager.start()
        return view
    }

    func updateUIView(_ uiView: ARView, context: Context) {}
}
