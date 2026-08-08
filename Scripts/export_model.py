"""在 macOS 上导出 YOLOv8n CoreML 模型（含 NMS，供 VNRecognizedObjectObservation 使用）。

Ultralytics 官方路径，Windows 上不可用（coremltools Windows wheel 缺少权重序列化组件）。
使用 YOLOv8n（nano 级、无 attention 层）而非 YOLO11n：11n 的 C2PSA 模块在
coremltools 转换中触发 'int' op 错误（8.4.116 + coremltools 9.0 已验证）。
"""
import os
import time

from ultralytics import YOLO

start = time.time()
model = YOLO("yolov8n.pt")
print(f"[export] model loaded in {time.time() - start:.1f}s", flush=True)

start = time.time()
path = str(model.export(format="coreml", imgsz=640, nms=True, half=True))
print(f"[export] coreml exported -> {path} in {time.time() - start:.1f}s", flush=True)

# 统一命名为 ObjectDetector.mlpackage
if not path.endswith("ObjectDetector.mlpackage"):
    os.system(f"mv '{path}' ObjectDetector.mlpackage")
print("[export] done", flush=True)
