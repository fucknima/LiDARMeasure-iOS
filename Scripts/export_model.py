"""在 macOS 上导出 YOLOv8n CoreML 模型（raw 输出 [1,84,8400]，不含 NMS）。

Windows 上无法导出（coremltools Windows wheel 缺少权重序列化组件）；
macOS 需 Python 3.12 以下（3.14 无 coremltools 二进制 wheel）。
使用 YOLOv8n（nano 级、无 attention 层）而非 YOLO11n：11n 的 C2PSA 模块在
coremltools 转换中触发 'int' op 错误（ultralytics 8.4.116 + coremltools 9.0 已验证）。

不启用 nms=True 的原因：Ultralytics 的 NMS 导出仅输出 confidence/coordinates
（无类别索引）且附带 iouThreshold/confidenceThreshold 两个额外输入，
VNCoreMLRequest 不支持多输入模型。raw 输出只有单一 image 输入，
由 App 内 YOLODecoder 完成 decode + NMS（成熟算法，任务书第 14 条允许）。
"""
import os
import time

from ultralytics import YOLO

start = time.time()
model = YOLO("yolov8n.pt")
print(f"[export] model loaded in {time.time() - start:.1f}s", flush=True)

start = time.time()
path = str(model.export(format="coreml", imgsz=640, half=True))
print(f"[export] coreml exported -> {path} in {time.time() - start:.1f}s", flush=True)

# 统一命名为 ObjectDetector.mlpackage
if not path.endswith("ObjectDetector.mlpackage"):
    os.system(f"mv '{path}' ObjectDetector.mlpackage")
print("[export] done", flush=True)
