# 项目状态

当前版本：`0.3.0`（build `3`）

仓库：https://github.com/fucknima/LiDARMeasure-iOS

## v0.3.0 整改内容

### 已修复的 v0.2.0 Bug

- [x] Bug 1：YOLO raw class index 偏移（classIndex - 4）已修正（旧 decoder 已删除）
- [x] Bug 2：raw 输出范围已由 `Scripts/test_coreml_output.py` 真实验证
      （YOLO26m-seg 输出为 640×640 像素 xyxy，非归一化；YOLOv8 为归一化 xywh）
- [x] Bug 3：`VNInstanceMaskObservation` 遍历改用 `allInstances`（观察索引不再当实例 ID）
- [x] Bug 4：统一 `CoordinateMapper` + `FrameGeometry`（camera/view/depth/mask 旋转与 displayTransform 对齐）
- [x] Bug 5：`ObjectTracker` 重写为 `TrackedObject(stableID)`，容忍丢失 ≤3 帧，
      用户选择基于 stableID 且优先级最高

### 模型升级

- [x] YOLO26m-seg CoreML（INT8，24MB）：FP16 与 INT8 检测结果完全一致 → 自动选用 INT8
- [x] YOLO26l-seg FP16 导出为 benchmark artifact（不进入正式 IPA）
- [x] `Scripts/ml-requirements.txt` 锁定依赖版本（ultralytics 8.4.116 / coremltools 9.0）
- [x] CoreML smoke test（fixture 图 → 8 detections + proto 非空）CI 必过
- [x] 模型随 App 打包（coremlcompiler preBuildScript），正式名为 `ObjectSegmenter.mlpackage`

### 新实现

- [x] `YOLO26SegDecoder`：preds [1,300,38] + proto [1,32,160,160] 解码、class-aware NMS、mask decode
- [x] `MLMultiArrayAccessor`：float16/float32/double 安全读取（废弃 bindMemory 脆弱实现）
- [x] 形状不匹配显式报错（modelOutputMismatch），禁止静默返回 []
- [x] YOLO mask 驱动 LiDAR 点云：mask 内深度直方图 + percentile 2%~98% + valley 断层裁剪
- [x] 智能框选 fallback：Apple 前景实例（allInstances）+ 无匹配时 ROI 深度聚类
- [x] 状态机补 segmenting / collectingDepth；热降频（serious/critical）
- [x] Debug Overlay 升级（Model/Inference/Track ID/Mask coverage/Points raw+filtered/Thermal）
- [x] 坐标 Debug 模式：绿色 YOLO box / 蓝色 Mask bounds / 黄色 Depth ROI
- [x] 单元测试 47 个全过（decoder/NMS/mask/坐标映射/tracker 回归）

### CI / 发布

- [x] Export workflow 改名 `Export YOLO26m-seg CoreML`，依赖锁定
- [x] Build/Release：模型存在检查 + mlmodelc 进包检查 + v0.3.0 IPA
- [x] 合并 master、tag v0.3.0、Release 发布（IPA 21.8MB，含 ObjectSegmenter.mlmodelc 已验证）
- [x] 清理：误提交的 .pt 权重已从历史移除；旧 ObjectDetector.mlpackage 已删除

## 模型许可证

YOLO26m-seg 为 AGPL-3.0（与仓库 MIT 冲突，分发需按 AGPL 提供源码；闭源上架需换模型）。
详见 `MODEL_INFO.md`、`THIRD_PARTY_NOTICES.md`。测试图来自 Ultralytics assets（AGPL-3.0）。

## 开发环境限制

Windows 开发机无 Xcode/Swift；编译、测试、IPA 由 macOS GitHub Actions（Xcode 16.4）完成。
模型导出必须走 macOS（Windows coremltools 无权重序列化组件；macOS runner 需 Python 3.12）。
真实 Detection / LiDAR 效果需 LiDAR 真机验证（`BENCHMARK.md`、`MEASUREMENT_TESTS.md` 待填）。

## 下一步

1. 真机验证：坐标 Debug 三层 overlay 对齐、OBB 方向、锁定稳定性
2. 真机 Benchmark m-seg vs l-seg（`BENCHMARK.md`）
3. `MEASUREMENT_TESTS.md` 记录 chair/bottle/tv 实测误差
4. 迭代版本：project.yml 版本号 + tag v0.3.1 触发 Release
