# 模型信息（ObjectSegmenter）

## 基本信息

| 项目 | 内容 |
|---|---|
| 模型 | YOLO26m-seg（实例分割） |
| 来源 | Ultralytics 预训练权重 `yolo26m-seg.pt` |
| 上游仓库 | https://github.com/ultralytics/ultralytics |
| 许可证 | **AGPL-3.0**（含代码与权重） |
| ultralytics 版本 | 8.4.116（`Scripts/ml-requirements.txt` 锁定） |
| coremltools 版本 | 9.0 |
| 输入 | 640×640 RGB 图像（单 image 输入） |
| 输出 | 两个 tensor（见下） |
| 类别 | COCO 80 类（person、chair、bottle、tv、laptop 等） |
| 量化 | 见 `Scripts/export_yolo26_seg.py` 对比结果（FP16 / INT8 择优） |
| 文件 | `LiDARMeasure/ML/ObjectSegmenter.mlpackage` |

## CoreML 输出规格（已由 Scripts/test_coreml_output.py 真实验证）

```
OUTPUT preds  [1, 300, 38]   NMS 后 top-300 检测
  通道 0~3:   xyxy（640x640 输入空间像素值）
  通道 4:     confidence
  通道 5:     class index
  通道 6~37:  32 个 mask coefficients
OUTPUT proto  [1, 32, 160, 160]  mask prototypes
```

**重要**：YOLO26 输出为解码后的像素坐标（0~640），不是 YOLOv8 raw 的归一化
xywh；模型内置 NMS。Swift 端不再假定 `VNRecognizedObjectObservation`。

## 预处理

- `VNCoreMLRequest.imageCropAndScaleOption = .scaleFill`
- 实测（coco_bus.jpg）：scaleFill 与 letterbox 检测结果一致
  （均为 5 个目标，conf 0.94 vs 0.95），坐标转换最简单（模型归一化
  == 显示方向图像归一化空间）
- 模型名/输出 shape 在 App 启动 Debug 日志记录（`CoreMLSegmenter`）

## 为什么 YOLO26m-seg

- 比 v0.2.0 的 YOLOv8n（detect）识别能力更强（m 档）
- 直接输出实例分割 mask，比 bounding box 更适合 LiDAR 点云裁剪
- 相比 x/l 档，持续推理负载更适合同时运行 ARKit/LiDAR 的 App

## 备用 Benchmark 模型

- YOLO26l-seg：仅导出为 CI artifact（`ObjectSegmenter-L-mlpackage-benchmark`），
  不进入正式 IPA。真机对比结果记录在 `BENCHMARK.md`，数据充分前正式模型
  保持 m-seg（任务书第 82 条）。

## CoreML 导出命令（macOS）

```bash
pip install -r Scripts/ml-requirements.txt
python Scripts/export_yolo26_seg.py   # 输出 ObjectSegmenter.mlpackage
```

核心步骤：

```python
from ultralytics import YOLO
model = YOLO("yolo26m-seg.pt")
model.export(format="coreml", imgsz=640, quantize="fp16")  # 或 quantize=8
```

## 许可证注意事项

**AGPL-3.0** 具有传染性：本项目（LICENSE 为 MIT）嵌入该模型后，对外分发
（包括侧载 IPA）时需按 AGPL-3.0 提供源码。若未来需要闭源上架 App Store，
必须替换为 Apache-2.0 / MIT / BSD 许可的检测模型（如 YOLOX-nano）。
