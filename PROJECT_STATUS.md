# 项目状态

当前版本：`0.2.0`（build `2`）

仓库：https://github.com/fucknima/LiDARMeasure-iOS
分支：`feature/real-object-detection`（待 CI Green 后合并 master）

## v0.2.0 整改内容（进行中）

将「Saliency 伪检测」彻底重构为「真实 CoreML 目标检测」流水线：

- [x] CoreML YOLOv8n（COCO 80 类，内置 NMS）随 App 打包（`LiDARMeasure/ML/ObjectDetector.mlpackage`）
- [x] macOS CI 导出模型 workflow（`export-model.yml` + `Scripts/export_model.py`）
- [x] ObjectDetector 重写：`MLModel + VNCoreMLModel + VNCoreMLRequest`，输出真实 BoundingBox + Label + Confidence
- [x] 目标跨帧跟踪（IoU + 类别 + 中心距离，保持稳定 ID）
- [x] 实例分割按 IoU 匹配 YOLO 检测框（FinalMask = 检测框 ∩ 实例掩码），禁止整张前景 mask
- [x] 深度直方图 dominant peak 动态前景带（不再固定 ±10cm），validDepthRatio 统计
- [x] PointCloudBuilder 重构：只扫目标 ROI、内参按深度图分辨率缩放、mask 采样、深度有效率
- [x] 重力对齐 OBB（PCA2D 闭式解）+ 1%~99% percentile 裁剪
- [x] 自动测量状态机（searching/detected/measuring/stabilizing/locked/failed）+ 明确失败提示
- [x] 时间稳定器（12 帧中位数，三轴 <3% 持续 8 帧锁定）
- [x] 智能框选模式：ROI + 前景分割 + 深度聚类（YOLO 不认识物体的兜底）
- [x] 检测框 UI（选中绿色 + 中文类别 + 置信度）、点击锁定目标
- [x] Debug 覆盖层：Detector/Objects/Selected/Mask/Depth/Valid depth/Points/OBB/Size
- [x] 设置页检测阈值（0.2~0.8，默认 0.35）
- [x] COCO 80 类中文映射
- [x] 单元测试更新（OBB/PCA/tracker/mapping/stabilizer）
- [x] CI：模型存在性检查 + mlmodelc 编译进 app 检查
- [ ] 模型 artifact 下载入库
- [ ] 分支 CI Green → 合并 master
- [ ] tag v0.2.0 → Release → IPA 校验

## 模型许可证

YOLOv8n 为 AGPL-3.0（与仓库 MIT 冲突，分发需按 AGPL 提供源码；闭源上架需换模型）。
详见 `MODEL_INFO.md`、`THIRD_PARTY_NOTICES.md`。

## 开发环境限制

Windows 开发机无 Xcode/Swift；编译、测试、IPA 由 macOS GitHub Actions（Xcode 16.4）完成。
模型导出必须走 macOS（Windows coremltools 无权重序列化组件；macOS runner 需 Python 3.12 以下，
3.14 无 coremltools 二进制 wheel）。真实 Detection / LiDAR 精度需 LiDAR 真机验证。

## 下一步

1. 真机验证：YOLO 检测框与 AR 画面坐标对齐（aspectFill 裁剪）、掩码匹配、OBB 方向
2. `MEASUREMENT_TESTS.md` 记录 chair/bottle/tv 等 COCO 物体的实测误差
3. 纸箱/工控柜用智能框选模式验证
4. 迭代版本：project.yml 版本号 + tag v0.2.1 触发 Release
