# LiDARMeasure

基于 ARKit / RealityKit / RoomPlan / Vision / CoreML 的 iOS 智能物体尺寸测量 App。

打开 App → 摄像头进入 AR 模式 → 自动识别物体 → 利用 LiDAR / SceneDepth 深度数据构建点云 → 计算并显示 宽 / 高 / 深。

## 功能

- **自动识别**：CoreML YOLOv8n 真实目标检测（COCO 80 类，模型内置 NMS）→ 检测框 + 类别 + 置信度
- **实例分割匹配**：Vision 前景实例分割，按 IoU 匹配 YOLO 检测框对应的实例，FinalMask = 检测框 ∩ 实例掩码
- **目标跟踪**：IoU + 类别 + 中心距离跨帧关联，保持稳定 ID；点击检测框可锁定目标
- **深度直方图前景分离**：ROI 内深度直方图 dominant peak 动态确定前景深度带，不固定 ±10cm
- **重力对齐 OBB**：Y 轴 = 高度，水平面 2D PCA 求长/宽，1%~99% percentile 裁剪离群点
- **时间稳定 + 自动锁定**：最近 12 帧中位数平滑，三轴变化 <3% 持续 8 帧后锁定
- **自动测量状态机**：searching → detected → measuring → stabilizing → locked / failed，各阶段给出明确提示
- **智能框选**：YOLO 不认识的物体（纸箱、工控柜等），拖框 + 前景分割 + 深度聚类测量
- **手动长度 / 手动长宽高**：点选测距，YOLO 不可用时的兜底
- **RoomPlan 引擎**：LiDAR 设备上直接复用系统识别的物体类别、dimensions、transform
- **Debug 覆盖层**：Detector / Objects / Selected / Mask / Depth / Valid depth / Points / OBB / Size
- **检测阈值**：设置页可调 0.2~0.8（默认 0.35）
- 测量历史（JSON）、截图（Documents + Photos）、单位 mm/cm/m/inch、校准测试、能力检测

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
├── AR             # ARSessionManager / DepthReader / DepthCoordinateMapper / PointCloudBuilder / RaycastService / ARRenderer
├── Vision         # ObjectDetector(VNCoreMLRequest) / ObjectSegmenter / ObjectTracker / VisionInferenceService / 坐标映射 / COCO 翻译
├── Measurement    # AutoMeasureCoordinator / AutoMeasureState / DimensionStabilizer
├── Geometry       # RobustStatistics / GravityAlignedOBB / PCA2D / BoundingBox3D
├── RoomPlan       # RoomPlanService
├── Services       # CapabilityService / HistoryStore / ScreenshotService
└── Utilities      # AppLog (OSLog)
```

MVVM + Services + Coordinator，矩阵/统计计算使用 `simd` 与 `Accelerate`（vDSP）。

## 模型与许可证

- 检测模型：Ultralytics YOLOv8n（COCO 80 类，含 NMS），`LiDARMeasure/ML/ObjectDetector.mlpackage`
- 模型许可证：**AGPL-3.0**（权重与代码）。嵌入本模型后对外分发需按 AGPL-3.0 提供源码；
  若未来需闭源上架，必须替换为宽松许可证模型。详见 `MODEL_INFO.md` 与 `THIRD_PARTY_NOTICES.md`
- 模型导出：macOS（含 GitHub Actions workflow），见 `Scripts/export_model.py`

## 开源依赖与许可

- 检测模型 YOLOv8n 为 AGPL-3.0（见 `MODEL_INFO.md`、`THIRD_PARTY_NOTICES.md`）
- 其余核心能力全部来自 Apple SDK，无第三方代码复用

## 测量限制

ARKit / LiDAR 是辅助测量工具，精度受以下因素影响：

- 物体距离（推荐 0.3 ~ 3 m）
- 材质与反光、透明物体、黑色物体
- 光照条件与观察角度
- 手机移动速度与 Tracking 状态

请勿将本工具用于工业计量。具体误差请使用「设置 → 校准测试」在本机实测。

## 已知问题

- Windows 环境无 Xcode/Swift，编译与 IPA 由 macOS CI 完成；最终精度需 LiDAR 真机验证
- YOLO 检测框 / 实例掩码 / 深度图的坐标系对齐需真机验证（Vision 输出为旋转后图像归一化坐标）
- RoomPlan 类别为系统枚举字符串，后续可补充本地化映射
- COCO 模型不识别纸箱、工控柜等工业物体 → 使用智能框选模式
- 自动模式输出为基于可见 LiDAR 点云的**估算尺寸**，不是 CAD 精确尺寸

## 测试记录

真实设备测量记录见 `MEASUREMENT_TESTS.md`。

## Roadmap

1. LiDAR 真机验证：检测框对齐、RoomPlan 类别、OBB 方向、校准测试记录
2. 评估 YOLOv8n vs YOLOv8s 精度/速度，必要时按设备动态选择模型
3. 网格重建展示与 OBJ 导出
4. 历史记录 UI 截图缩略图
5. 若需闭源上架：替换 AGPL 模型为宽松许可证模型（如 YOLOX-nano）

## 项目状态

见 `PROJECT_STATUS.md`。
