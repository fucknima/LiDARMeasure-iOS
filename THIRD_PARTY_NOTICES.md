# Third Party Notices

LiDARMeasure 没有复制任何第三方仓库的源代码；核心能力全部来自 Apple SDK（ARKit、RealityKit、RoomPlan、Vision、Accelerate、simd、AVFoundation、Photos、OSLog）。因此没有需要随本仓库分发的第三方源代码许可证文件。

## 参考的 Apple 官方 Sample（仅参考思路，未复制源文件）

- [Displaying a point cloud using scene depth](https://developer.apple.com/documentation/arkit/displaying-a-point-cloud-using-scene-depth) — Apple Sample Code License
  Used for: SceneDepth、confidenceMap、深度像素 → 相机坐标反投影思路

- [Recognizing Objects in Live Capture](https://developer.apple.com/documentation/vision/recognizing-objects-in-live-capture) — Apple Sample Code License
  Used for: Vision 请求流程与归一化 bounding box 坐标约定

- [Scanning a room with RoomPlan](https://developer.apple.com/documentation/roomplan/scanning-a-room-with-roomplan) — Apple Sample Code License
  Used for: RoomCaptureSession / CapturedRoom 使用方式

Modified: N/A（本项目独立实现）

## 调研但未复用的 GitHub 项目

以下项目仅用于比较 API 组织方式与许可证，不复制其源代码：

- [cedanmisquith/SwiftUI-LiDAR](https://github.com/cedanmisquith/SwiftUI-LiDAR) — MIT，偏场景网格扫描与 OBJ 导出
- [holg/RoomPlanExampleApp](https://github.com/holg/RoomPlanExampleApp) — RoomPlan 示例，仅参考 README 组织
- [philipturner/lidar-scanning-app](https://github.com/philipturner/lidar-scanning-app) — MIT，偏网格扫描导出，未复用

本项目最终选择 Apple SDK 官方实现，以降低旧 API、外部依赖与许可证传播风险。

## App 图标

图标为项目自绘（立方体 + 尺寸箭头），无版权争议。
