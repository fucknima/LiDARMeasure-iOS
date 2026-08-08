# YOLO26m-seg vs YOLO26l-seg Benchmark

本文件记录真机性能对比。CI 只验证编译与 CoreML smoke test；
推理延迟、发热、Mask 质量必须由真实 iPhone 记录。

## 字段模板

| 字段 | 值 |
|---|---|
| Device | 例如 iPhone 12 Pro / iPhone 15 Pro |
| iOS | 例如 17.5 |
| Model | YOLO26m-seg / YOLO26l-seg |
| Quantization | FP16 / INT8 |
| Input | 640×640 |
| Average inference ms | |
| P95 inference ms | |
| Detection result | 测试场景与检测数 |
| Mask quality | 边缘贴合程度（好/中/差） |
| Thermal after 5 min | nominal / fair / serious |
| Recommendation | m / l |

## 如何获取 l-seg 模型

从 GitHub Actions artifact 下载 `ObjectSegmenter-L-mlpackage-benchmark`，
替换 `LiDARMeasure/ML/ObjectSegmenter.mlpackage` 后重新构建（仅用于真机测试，
不进入正式 IPA）。

## 记录

（待 LiDAR 真机填写。正式模型保持 m-seg，直到真机数据证明 l-seg 值得。）
