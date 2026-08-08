"""在 macOS 上导出 YOLO11n CoreML 模型（含 NMS，供 VNRecognizedObjectObservation 使用）。

Ultralytics 官方路径，Windows 上不可用（coremltools Windows wheel 缺少权重序列化组件）。
"""
import os
import time

from ultralytics import YOLO

start = time.time()
model = YOLO("yolo11n.pt")
print(f"[export] model loaded in {time.time() - start:.1f}s", flush=True)

start = time.time()
path = model.export(format="coreml", imgsz=640, nms=True, half=True)
print(f"[export] coreml exported -> {path} in {time.time() - start:.1f}s", flush=True)

# 统一命名为 ObjectDetector.mlpackage
if not path.endswith("ObjectDetector.mlpackage"):
    os.system(f"mv '{path}' ObjectDetector.mlpackage")
print("[export] done", flush=True)
