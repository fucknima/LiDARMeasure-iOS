# Third Party Notices

LiDARMeasure 核心代码未复制第三方仓库源代码；核心能力来自 Apple SDK
（ARKit、RealityKit、RoomPlan、Vision、CoreML、Accelerate、simd、AVFoundation、Photos、OSLog）。

## ObjectDetector CoreML 模型（YOLOv8n）

- 来源：Ultralytics 预训练权重 `yolov8n.pt`（https://github.com/ultralytics/ultralytics）
- License: **AGPL-3.0**（权重与代码）
- 用途：自动模式目标检测（COCO 80 类，含 NMS）
- 导出：`Scripts/export_model.py`（macOS，见 `MODEL_INFO.md`）
- Modified: 无（仅转换格式为 CoreML mlpackage）

**许可证影响**：本仓库 LICENCE 为 MIT，嵌入 AGPL-3.0 模型后对外分发需按
AGPL-3.0 提供源码；未来若需闭源上架，必须替换为宽松许可证模型（见 MODEL_INFO.md）。

## 参考的 Apple 官方 Sample（仅参考思路，未复制源文件）

- [Displaying a point cloud using scene depth](https://developer.apple.com/documentation/arkit/displaying-a-point-cloud-using-scene-depth) — Apple Sample Code License
  Used for: SceneDepth、confidenceMap、深度像素 → 相机坐标反投影思路

- [Recognizing Objects in Live Capture](https://developer.apple.com/documentation/vision/recognizing-objects-in-live-capture) — Apple Sample Code License
  Used for: Vision 请求流程与归一化 bounding box 坐标约定

- [Scanning a room with RoomPlan](https://developer.apple.com/documentation/roomplan/scanning-a-room-with-roomplan) — Apple Sample Code License
  Used for: RoomCaptureSession / CapturedRoom 使用方式

- [Generating a Foreground Instance Mask](https://developer.apple.com/documentation/vision/generating-a-foreground-instance-mask) — Apple Sample Code License
  Used for: VNGenerateForegroundInstanceMaskRequest 实例匹配思路

Modified: N/A（本项目独立实现）

## 调研但未复用的 GitHub 项目

以下项目仅用于比较 API 组织方式与许可证，不复制其源代码：

- [cedanmisquith/SwiftUI-LiDAR](https://github.com/cedanmisquith/SwiftUI-LiDAR) — MIT，偏场景网格扫描与 OBJ 导出
- [holg/RoomPlanExampleApp](https://github.com/holg/RoomPlanExampleApp) — RoomPlan 示例，仅参考 README 组织
- [philipturner/lidar-scanning-app](https://github.com/philipturner/lidar-scanning-app) — MIT，偏网格扫描导出，未复用
- [Ultralytics YOLOv8](https://github.com/ultralytics/ultralytics) — AGPL-3.0，仅用于导出模型权重，未复制训练/推理代码

本项目最终选择 Apple SDK 官方实现 + Ultralytics 预训练模型，
以降低旧 API 与外部依赖风险。

## App 图标

图标为项目自绘（立方体 + 尺寸箭头），无版权争议。
