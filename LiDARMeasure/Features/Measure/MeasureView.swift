import RealityKit
import SwiftUI

struct MeasureView: View {
    @ObservedObject var viewModel: MeasureViewModel
    @State private var gestureStart: CGPoint = .zero

    var body: some View {
        ZStack {
            cameraLayer
                .ignoresSafeArea()

            overlayContent
        }
        .background(Color.black)
    }

    // MARK: - 相机层

    private var cameraLayer: some View {
        Group {
            if viewModel.mode == .roomScan {
                RoomCaptureViewContainer(service: viewModel.roomPlanService)
            } else {
                ARViewContainer(viewModel: viewModel)
            }
        }
        .contentShape(Rectangle())
        .gesture(dragGesture)
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if viewModel.mode == .boxSelection {
                    viewModel.beginSelection(at: value.startLocation)
                    viewModel.updateSelection(to: value.location)
                } else {
                    gestureStart = value.startLocation
                }
            }
            .onEnded { value in
                switch viewModel.mode {
                case .boxSelection:
                    viewModel.endSelection()
                case .automatic:
                    let distance = hypot(
                        value.location.x - gestureStart.x,
                        value.location.y - gestureStart.y
                    )
                    if distance < 10 {
                        viewModel.selectAutoTarget(at: value.location)
                    }
                case .manualLength, .manualDimensions:
                    let distance = hypot(
                        value.location.x - gestureStart.x,
                        value.location.y - gestureStart.y
                    )
                    if distance < 10 {
                        viewModel.handleTap(at: value.location)
                    }
                case .roomScan:
                    break
                }
            }
    }

    // MARK: - 覆盖层

    private var overlayContent: some View {
        GeometryReader { proxy in
            ZStack {
                VStack {
                    topBar
                    Spacer()
                    centerHint
                    Spacer()
                    detectionOverlay(in: proxy.size)
                    if viewModel.showDebugOverlay {
                        debugOverlay
                    }
                    resultCard
                    modeSelector
                    actionBar
                }
                .padding(.horizontal, 12)

                if let rect = viewModel.selectionRect, viewModel.mode == .boxSelection {
                    Rectangle()
                        .fill(Color.cyan.opacity(0.12))
                        .overlay(Rectangle().stroke(Color.cyan, lineWidth: 2))
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                }
            }
            .onAppear {
                viewModel.setViewportSize(proxy.size)
            }
            .onChange(of: proxy.size) { _, newSize in
                viewModel.setViewportSize(newSize)
            }
        }
    }

    /// 真实检测框：选中目标绿色，其余白色，标注中文类别与置信度。
    private func detectionOverlay(in size: CGSize) -> some View {
        Group {
            if viewModel.mode == .automatic, !viewModel.detections.isEmpty {
                ForEach(viewModel.detections) { object in
                    let viewBox = VisionCoordinateMapper.viewBox(
                        from: VisionCoordinateMapper.topLeft(object.boundingBox),
                        in: size
                    )
                    let isSelected = object.id == viewModel.selectedObjectID
                    Rectangle()
                        .stroke(isSelected ? Color.green : Color.white.opacity(0.8), lineWidth: isSelected ? 2.5 : 1.5)
                        .frame(width: viewBox.width, height: viewBox.height)
                        .position(x: viewBox.midX, y: viewBox.midY)
                        .overlay(alignment: .top) {
                            Text(labelText(for: object, isSelected: isSelected))
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.black)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(isSelected ? Color.green : Color.white.opacity(0.85))
                                .cornerRadius(4)
                                .offset(y: -2)
                        }
                }
            }
        }
    }

    private func labelText(for object: DetectedObject, isSelected: Bool) -> String {
        let name = COCOLabelTranslator.translate(object.label)
        if viewModel.showDebugOverlay || isSelected {
            return "\(name) \(Int(object.confidence * 100))%"
        }
        return name
    }

    private var topBar: some View {
        HStack {
            Text("LiDAR Measure")
                .font(.headline)
                .foregroundStyle(.white)
            Spacer()
            capabilityBadge
            if viewModel.mode == .roomScan {
                Button("结束扫描") {
                    viewModel.stopRoomScan()
                }
                .buttonStyle(.borderedProminent)
                .tint(.cyan)
            }
        }
        .padding(.top, 8)
    }

    private var capabilityBadge: some View {
        Text(viewModel.capabilities.lidarAvailable ? "LiDAR" : "普通 AR")
            .font(.caption)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(viewModel.capabilities.lidarAvailable ? Color.green.opacity(0.85) : Color.orange.opacity(0.85))
            )
            .foregroundStyle(.white)
    }

    private var centerHint: some View {
        Group {
            if viewModel.mode == .automatic || viewModel.mode == .boxSelection {
                CrosshairView()
                    .stroke(.white.opacity(0.85), lineWidth: 1.5)
                    .frame(width: 44, height: 44)
            }
        }
    }

    private var debugOverlay: some View {
        let debug = viewModel.pipelineDebug
        return VStack(alignment: .leading, spacing: 2) {
            Text("Detector: \(debug.detectorOn ? "ON" : "OFF")")
            Text("Objects: \(debug.objectCount)")
            if let label = debug.selectedLabel {
                Text("Selected: \(COCOLabelTranslator.translate(label)) \(debug.selectedConfidence.map { String(format: "%.2f", $0) } ?? "-")")
            }
            Text("Mask: \(debug.hasMask ? "YES" : "NO")")
            Text("Depth: \(debug.hasDepth ? "YES" : "NO")")
            Text(String(format: "Valid depth: %.0f%%", debug.validDepthRatio * 100))
            Text("Points: \(debug.pointCount)")
            Text("OBB: \(debug.hasOBB ? "YES" : "NO")")
            if let formatted = viewModel.formattedDimensions {
                Text("Size: \(formatted)")
            }
            Text("Tracking: \(viewModel.sessionManager.trackingState)")
            if let quality = viewModel.quality {
                Text("Quality: \(quality.grade.rawValue) (\(String(format: "%.2f", quality.score)))")
            }
        }
        .font(.caption2.monospaced())
        .foregroundStyle(.white)
        .padding(8)
        .background(Color.black.opacity(0.55))
        .cornerRadius(8)
    }

    private var resultCard: some View {
        VStack(spacing: 6) {
            if let formatted = viewModel.formattedDimensions ?? viewModel.formattedDistance {
                Text(formatted)
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.white)
            } else {
                Text("—")
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.5))
            }
            if let quality = viewModel.quality {
                Text(quality.grade.rawValue)
                    .font(.caption)
                    .foregroundStyle(qualityColor(quality.grade))
            }
            Text(viewModel.statusText)
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.8))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .cornerRadius(14)
    }

    private func qualityColor(_ grade: MeasurementQualityGrade) -> Color {
        switch grade {
        case .excellent: return .green
        case .good: return .cyan
        case .poor: return .orange
        }
    }

    private var modeSelector: some View {
        HStack(spacing: 8) {
            ForEach(MeasurementMode.allCases) { mode in
                Button {
                    viewModel.mode = mode
                } label: {
                    Text(mode.displayName)
                        .font(.subheadline.weight(viewModel.mode == mode ? .semibold : .regular))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(viewModel.mode == mode ? Color.cyan : Color.white.opacity(0.15))
                        )
                        .foregroundStyle(viewModel.mode == mode ? Color.black : Color.white)
                }
            }
        }
        .padding(.vertical, 6)
    }

    private var actionBar: some View {
        HStack(spacing: 16) {
            Button {
                viewModel.undo()
            } label: {
                Label("撤销", systemImage: "arrow.uturn.backward")
            }
            Button {
                viewModel.clear()
            } label: {
                Label("清除", systemImage: "xmark")
            }
            Button {
                Task { await viewModel.save() }
            } label: {
                Label("保存", systemImage: "square.and.arrow.down")
            }
            .disabled(viewModel.isSaving || (viewModel.distanceMeters == nil && viewModel.currentDimensionsForSave == nil))
        }
        .font(.subheadline)
        .buttonStyle(.bordered)
        .tint(.cyan)
        .padding(.bottom, 8)
    }
}

struct CrosshairView: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        path.addEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.midY - 6))
        path.move(to: CGPoint(x: rect.midX, y: rect.midY + 6))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.midX - 6, y: rect.midY))
        path.move(to: CGPoint(x: rect.midX + 6, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path
    }
}
