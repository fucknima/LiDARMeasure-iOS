# 模型信息（ObjectDetector）

## 基本信息

| 项目 | 内容 |
|---|---|
| 模型 | YOLOv8n（nano 级目标检测） |
| 来源 | Ultralytics 预训练权重 `yolov8n.pt` |
| 上游仓库 | https://github.com/ultralytics/ultralytics |
| 许可证 | **AGPL-3.0**（含代码与权重） |
| 版本 | ultralytics 8.4.x 导出 |
| 输入 | 640×640 RGB 图像 |
| 输出 | 内置 NMS 的目标检测结果（labels + boundingBox + confidence） |
| 类别 | COCO 80 类（person、chair、bottle、tv、laptop 等） |
| 参数量 | 3.2M（2,616,248 参数） |
| 计算量 | 6.5 GFLOPs |
| 量化 | FP16（half） |
| 文件 | `LiDARMeasure/ML/ObjectDetector.mlpackage` |

## 许可证注意事项

**AGPL-3.0** 具有传染性：本项目（LICENSE 为 MIT）嵌入该模型后，对外分发
（包括侧载 IPA）时需按 AGPL-3.0 提供源码。若未来需要闭源上架 App Store，
必须替换为 Apache-2.0 / MIT / BSD 许可的检测模型（如 YOLOX-nano）。

## CoreML 导出命令（macOS）

Windows 上无法导出（coremltools Windows wheel 缺少权重序列化组件）；
GitHub Actions 的 macOS runner 可执行（见 `.github/workflows/export-model.yml`）。

```bash
pip install ultralytics coremltools
python Scripts/export_model.py   # 输出 ObjectDetector.mlpackage
```

核心步骤（ultralytics 官方路径）：

```python
from ultralytics import YOLO
model = YOLO("yolov8n.pt")
model.export(format="coreml", imgsz=640, nms=True, half=True)
```

## 为什么不使用 YOLO11n

YOLO11n 的 C2PSA（attention）模块在 coremltools 转换中触发
`'int' op` 转换错误（ultralytics 8.4.116 + coremltools 9.0 实测）。
YOLOv8n 为 nano 级、无 attention，CoreML 导出链路最成熟，
且同为 COCO 80 类，Swift 端无需调整类别表。

## 推理方式

- 框架：`MLModel(contentsOf:)` + `VNCoreMLModel` + `VNCoreMLRequest`
- 预处理：Vision 负责 YUV→RGB 与 640×640 缩放（`imageCropAndScaleOption = .scaleFill`）
- 输出：`VNRecognizedObjectObservation`（模型内置 NMS，App 不重复做）
- 阈值：默认 0.35，设置页可调 0.2~0.8
