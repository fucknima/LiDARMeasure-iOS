import Combine
import Foundation
import RoomPlan
import simd
import SwiftUI

struct RoomObjectMeasurement {
    let category: String
    let dimensions: MeasurementDimensions
    let transform: simd_float4x4
}

@MainActor
final class RoomPlanService: NSObject, ObservableObject, RoomCaptureSessionDelegate {
    @Published private(set) var measurements: [RoomObjectMeasurement] = []
    @Published private(set) var isScanning = false
    @Published private(set) var lastError: String?

    private var session: RoomCaptureSession?
    private var startWhenAttached = false

    func attach(to session: RoomCaptureSession) {
        self.session = session
        session.delegate = self
        if startWhenAttached {
            start()
        }
    }

    func start() {
        guard RoomCaptureSession.isSupported else {
            lastError = "当前设备不支持 RoomPlan"
            AppLog.roomPlan.error("RoomPlan unsupported on this device")
            return
        }
        guard let session else {
            startWhenAttached = true
            return
        }
        startWhenAttached = false
        session.run(configuration: RoomCaptureSession.Configuration())
        isScanning = true
        lastError = nil
        AppLog.roomPlan.info("RoomPlan capture started")
    }

    func stop() {
        startWhenAttached = false
        session?.stop()
        isScanning = false
        AppLog.roomPlan.info("RoomPlan capture stopped, objects=\(self.measurements.count)")
    }

    func captureSession(_ session: RoomCaptureSession, didUpdate room: CapturedRoom) {
        update(with: room)
    }

    func captureSession(_ session: RoomCaptureSession, didAdd room: CapturedRoom) {
        update(with: room)
    }

    func captureSession(_ session: RoomCaptureSession, didChange room: CapturedRoom) {
        update(with: room)
    }

    func captureSession(_ session: RoomCaptureSession, didRemove room: CapturedRoom) {
        // didRemove 只包含移除子集，保留 didUpdate 的完整快照。
    }

    func captureSession(_ session: RoomCaptureSession, didEndWith data: CapturedRoomData, error: (any Error)?) {
        isScanning = false
        if let error {
            lastError = "RoomPlan：\(error.localizedDescription)"
            AppLog.roomPlan.error("RoomPlan ended with error: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func update(with room: CapturedRoom) {
        measurements = room.objects.map { object in
            RoomObjectMeasurement(
                category: String(describing: object.category),
                dimensions: MeasurementDimensions(
                    width: abs(object.dimensions.x),
                    height: abs(object.dimensions.y),
                    depth: abs(object.dimensions.z)
                ),
                transform: object.transform
            )
        }
        AppLog.roomPlan.info("RoomPlan updated, objects=\(self.measurements.count)")
    }
}

struct RoomCaptureViewContainer: UIViewRepresentable {
    let service: RoomPlanService

    func makeUIView(context: Context) -> RoomCaptureView {
        let view = RoomCaptureView(frame: .zero)
        service.attach(to: view.captureSession)
        return view
    }

    func updateUIView(_ uiView: RoomCaptureView, context: Context) {}
}
