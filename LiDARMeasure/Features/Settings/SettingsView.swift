import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: MeasureViewModel
    @State private var realValueText = ""
    @State private var calibrationResult: String?

    private let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-"
    private let buildNumber = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "-"

    var body: some View {
        NavigationStack {
            Form {
                Section("单位") {
                    Picker("测量单位", selection: $viewModel.unit) {
                        ForEach(MeasurementUnit.allCases) { unit in
                            Text(unit.displayName).tag(unit)
                        }
                    }
                    .pickerStyle(.menu)
                }

                Section("自动检测") {
                    VStack(alignment: .leading) {
                        Text(String(format: "检测阈值：%.0f%%", viewModel.detectionThreshold * 100))
                        Slider(value: $viewModel.detectionThreshold, in: 0.2...0.8, step: 0.05)
                        Text("低于阈值的检测结果将被忽略。默认 35%，调试时可降低到 20%。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if !viewModel.pipelineDebug.detectorOn {
                        Label("检测模型加载失败", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                    }
                }

                Section("设备能力") {
                    ForEach(viewModel.capabilities.summary, id: \.self) { item in
                        Text(item)
                    }
                }

                Section("调试") {
                    Toggle("Debug 覆盖层", isOn: $viewModel.showDebugOverlay)
                    Toggle("坐标 Debug（绿框/蓝 Mask/黄 ROI）", isOn: $viewModel.showCoordinateDebug)
                }

                Section("校准测试") {
                    Text("测量一个已知尺寸物体（如 A4 纸 21.0 cm 宽、银行卡 8.56 cm 宽），在下方输入真实值（cm），对比测量误差。App 不会自动修改比例。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    TextField("真实宽度（cm）", text: $realValueText)
                        .keyboardType(.decimalPad)
                    Button("计算误差") {
                        calculateError()
                    }
                    if let calibrationResult {
                        Text(calibrationResult)
                            .font(.footnote)
                    }
                }

                Section("关于") {
                    LabeledContent("版本", value: "\(appVersion) (\(buildNumber))")
                    LabeledContent("精度说明") {
                        Text("LiDAR/ARKit 是辅助测量工具。精度受距离、材质、光照、角度、反光、透明与黑色物体影响，请勿当作工业计量工具。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
                    }
                }
            }
            .navigationTitle("设置")
        }
    }

    private func calculateError() {
        guard let realValue = Float(realValueText.replacingOccurrences(of: ",", with: ".")),
              realValue > 0,
              let measured = viewModel.dimensions else {
            calibrationResult = "请输入真实值并先完成一次测量"
            return
        }
        let measuredCM = MeasurementUnit.centimeter.value(fromMeters: measured.width)
        let error = (measuredCM - realValue) / realValue * 100
        calibrationResult = String(
            format: "测量 %.1f cm，真实 %.1f cm，误差 %+.1f%%",
            measuredCM, realValue, error
        )
        AppLog.measure.info(
            "Calibration: measured=\(measuredCM)cm real=\(realValue)cm error=\(error)%"
        )
    }
}
