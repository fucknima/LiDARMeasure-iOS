# LiDARMeasure

基于 ARKit / RealityKit / RoomPlan / Vision 的 iOS 智能物体尺寸测量 App。

打开 App → 摄像头进入 AR 模式 → 自动识别物体 → 利用 LiDAR / SceneDepth 深度数据构建点云 → 计算并显示 宽 / 高 / 深。

## 功能

- **自动模式**：Vision 显著性检测 + 前景实例分割（iOS 17 内置能力，无模型体积）→ SceneDepth 点云 → 深度带过滤背景 → 重力对齐 OBB → 实时显示宽/高/深
- **框选模式**：手指拖框圈住物体，App 在 ROI 内用深度聚类计算尺寸
- **手动长度**：点击 A、B 两点，世界坐标距离
- **手动长宽高**：依次点击左下、右下、左上、后角，计算宽/高/深
- **RoomPlan 引擎**：LiDAR 设备上直接复用系统识别的物体类别、dimensions、transform
- **测量稳定器**：最近 15 帧中位数平滑，变化 < 2% 且持续数帧后显示「测量稳定」
- **质量评分**：综合 Tracking、深度置信度、有效点数、距离、稳定度 → 优秀/良好/较差
- **测量历史**：Codable + JSON 保存日期、模式、尺寸、单位、质量、截图路径
- **截图保存**：写入 Documents 并申请 Photos add-only 权限保存到图库
- **单位切换**：mm / cm / m / inch，默认 cm，内部统一米
- **设备能力检测**：全部通过 API capability 判断，不依赖机型
- **校准测试**：输入已知真实尺寸，显示测量误差百分比（不自动修改比例）
- **Debug 覆盖层**：Tracking / Depth / 点数 / 检测标签 / 质量

## 支持设备

- 最低部署目标：iOS 17
- **LiDAR 设备**（iPhone 12 Pro 及以上等）：启用 `sceneDepth` + `smoothedSceneDepth`，支持时启用 mesh reconstruction 与 RoomPlan
- **非 LiDAR 设备**：自动降级到平面检测 + raycast + 手动测量，显示「当前设备不支持 LiDAR，自动三维测量能力可能受限」，不崩溃

## 如何编译

```bash
brew install xcodegen
xcodegen generate
xcodebuild -project LiDARMeasure.xcodeproj -scheme LiDARMeasure -destination 'platform=iOS Simulator,name=iPhone 16' test CODE_SIGNING_ALLOWED=NO
xcodebuild -project LiDARMeasure.xcodeproj -scheme LiDARMeasure -configuration Release -sdk iphoneos -derivedDataPath build CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" build
```

`project.yml` 已提交，仓库永远可以重新生成工程。

## 如何安装 / 下载 IPA

1. 从 GitHub Releases 下载 `LiDARMeasure-vX.X.X-unsigned.ipa`
2. 使用侧载工具（如 AltStore、Sideloadly、TrollStore）签名安装到自己的 iPhone
3. 或者：用自己的开发者证书重新签名：`codesign -f -s "你的证书" -i com.lidarmeasure.app LiDARMeasure.app`

## GitHub Actions

- `.github/workflows/build.yml`：push / PR / workflow_dispatch 触发，生成工程 → 单元测试 → iphoneos Release 编译 → 打包 unsigned IPA 上传 artifact
- `.github/workflows/release.yml`：推送 `v*.*.*` tag 触发，测试 + 编译 + 打包 + 自动发布 GitHub Release
- 版本号：`project.yml` 中 `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION`

## 架构

```
LiDARMeasure
├── App            # 入口、Tab
├── Models         # 测量模型、单位、模式、能力
├── Features       # Measure / History / Settings
├── AR             # ARSessionManager / DepthReader / RaycastService / PointCloudBuilder / ARRenderer
├── Vision         # ObjectDetector / ObjectSegmenter / VisionPipeline
├── Geometry       # RobustStatistics / BoundingBox3D(OBB) / MeasurementSmoother
├── RoomPlan       # RoomPlanService
├── Services       # CapabilityService / HistoryStore / ScreenshotService / UnitSettings
└── Utilities      # AppLog (OSLog)
```

MVVM + Services，矩阵/统计计算使用 `simd` 与 `Accelerate`（vDSP）。

## 开源依赖与许可

本仓库未复制第三方开源项目源代码，全部核心能力来自 Apple SDK。调研过的 GitHub 项目与 Apple Sample 记录在 `THIRD_PARTY_NOTICES.md`。

## 测量限制

ARKit / LiDAR 是辅助测量工具，精度受以下因素影响：

- 物体距离（推荐 0.3 ~ 3 m）
- 材质与反光、透明物体、黑色物体
- 光照条件与观察角度
- 手机移动速度与 Tracking 状态

请勿将本工具用于工业计量。具体误差请使用「设置 → 校准测试」在本机实测。

## 已知问题

- Windows 环境无 Xcode/Swift，编译与 IPA 由 macOS CI 完成；最终精度需 LiDAR 真机验证
- 自动模式使用系统内置显著性/分类（非专用目标检测模型），未知物体会落入「框选 + 深度聚类」fallback
- RoomPlan 类别为系统枚举字符串，后续可补充本地化映射
- 深度像素↔屏幕坐标的 displayTransform 换算、前景掩码与深度图的坐标系对齐需真机验证

## Roadmap

1. LiDAR 真机验证：RoomPlan 类别、坐标转换、OBB 方向、校准测试记录
2. 可选 CoreML 目标检测模型（YOLO/Ultralytics 导出，检查体积与许可证）
3. 网格重建展示与 OBJ 导出
4. 历史记录 UI 截图缩略图
5. iPad 适配

## 项目状态

见 `PROJECT_STATUS.md`。
