# 项目状态

当前版本：`0.1.0`（build `1`）

仓库：https://github.com/fucknima/LiDARMeasure-iOS

## 已完成

- [x] XcodeGen 可重生成工程骨架（project.yml 已提交）
- [x] SwiftUI + MVVM + Services 目录结构
- [x] ARKit 能力检测与非 LiDAR 降级配置（全部 API capability 判断）
- [x] 手动长度与手动长宽高测量
- [x] SceneDepth / confidenceMap 深度采样与点云构建
- [x] 中位数 / MAD / IQR 离群过滤
- [x] 重力对齐 2D PCA 闭式解 OBB（simd + Accelerate vDSP）
- [x] 自动测量稳定器（15 帧中位数，<2% 判定稳定）与质量评分
- [x] Vision 显著性检测 + 前景实例分割（iOS 17 内置能力）
- [x] RoomPlan 结果适配（类别 / dimensions / transform）
- [x] 框选测量（拖框 ROI + 深度聚类）
- [x] JSON 测量历史、单位设置、截图保存、校准测试页
- [x] 单元测试（转换 / 统计 / 几何 / 平滑 / 质量）
- [x] GitHub Actions：build.yml + release.yml

## 开发环境限制

本次开发运行在 Windows，无 Xcode/Swift，无法本机执行 `xcodebuild`，也无真实 LiDAR iPhone。
编译、测试、unsigned IPA 均由 macOS GitHub Actions runner（Xcode 16.4）完成。
真实 LiDAR 精度与坐标转换需在真机上验证，见 README「已知问题」。

## 下一步

1. 在 macOS 本机 `brew install xcodegen && xcodegen generate && xcodebuild test`
2. LiDAR 真机验证：RoomPlan 类别、displayTransform 坐标换算、掩码对齐、OBB 方向
3. 使用 A4 / 银行卡等已知尺寸记录校准测试结果（App 不自动修改比例）
4. 迭代版本：修改 project.yml 的 MARKETING_VERSION / CURRENT_PROJECT_VERSION，推送 `v0.1.1` tag 触发 Release
