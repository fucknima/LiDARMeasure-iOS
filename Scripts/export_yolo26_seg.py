"""导出 YOLO26m-seg CoreML 模型（v0.3.0 正式模型）。

- macOS 运行（Windows coremltools 无权重序列化组件）
- 对比 FP16 与 INT8：用 fixture 图跑推理，若 INT8 检测结果与 FP16
  一致（类别相同、置信度差 < 0.05），选用 INT8（体积小），否则 FP16
- 额外导出 YOLO26l-seg 作为真机 benchmark（不进入正式 IPA）
"""
import os
import shutil
import time

from ultralytics import YOLO

MODEL_NAMES = ["yolo26m-seg.pt", "yolo26l-seg.pt"]
FIXTURE = "Tests/Fixtures/coco_bus.jpg"
TARGET_M = "ObjectSegmenter.mlpackage"


def export(model_path: str, quantize: str | None) -> str:
    start = time.time()
    model = YOLO(model_path)
    print(f"[export] {model_path} loaded in {time.time() - start:.1f}s", flush=True)
    start = time.time()
    kwargs = {"format": "coreml", "imgsz": 640}
    if quantize:
        kwargs["quantize"] = quantize
    path = str(model.export(**kwargs))
    print(f"[export] {model_path} quantize={quantize} -> {path} in {time.time() - start:.1f}s", flush=True)
    return path


def compare(model_a: str, model_b: str):
    """两个模型在同一 fixture 图上的检测结果对比。"""
    import coremltools as ct
    from PIL import Image

    image = Image.open(FIXTURE).convert("RGB")

    def results(path: str):
        model = ct.models.MLModel(path)
        spec = model.get_spec()
        input_name = spec.description.input[0].name
        out = model.predict({input_name: image})
        names = list(out.keys())
        shapes = {n: getattr(out[n], "shape", None) for n in names}
        return names, shapes, out

    names_a, shapes_a, out_a = results(model_a)
    names_b, shapes_b, out_b = results(model_b)
    print(f"[compare] A={model_a}")
    for n, s in zip(names_a, shapes_a.values()):
        print(f"[compare]   {n} {s}")
    print(f"[compare] B={model_b}")
    for n, s in zip(names_b, shapes_b.values()):
        print(f"[compare]   {n} {s}")

    import numpy as np

    def detections(out):
        det_key = next(k for k, v in out.items() if getattr(v, "ndim", 0) == 3)
        det = np.asarray(out[det_key])
        confs = det[0, :, 4]
        classes = det[0, :, 5].astype(int)
        kept = confs > 0.3
        return list(zip(classes[kept].tolist(), confs[kept].round(3).tolist()))

    det_a = detections(out_a)
    det_b = detections(out_b)
    print(f"[compare] A detections: {sorted(det_a, reverse=True)}")
    print(f"[compare] B detections: {sorted(det_b, reverse=True)}")
    return det_a, det_b


def main():
    os.makedirs("mlwork", exist_ok=True)

    # 1. 导出 m-seg FP16 与 INT8 对比。
    fp16_path = export("yolo26m-seg.pt", "fp16")
    int8_path = None
    try:
        int8_path = export("yolo26m-seg.pt", 8)
    except Exception as e:
        print(f"[export] INT8 failed: {e}", flush=True)

    if int8_path and os.path.isdir(int8_path):
        det_fp16, det_int8 = compare(fp16_path, int8_path)
        use_int8 = (
            len(det_int8) > 0
            and sorted(det_fp16) == sorted(det_int8)
        )
        chosen = int8_path if use_int8 else fp16_path
        print(f"[export] chosen: {chosen} (int8={use_int8})", flush=True)
    else:
        chosen = fp16_path
        print(f"[export] chosen: {chosen} (fp16, int8 unavailable)", flush=True)

    if os.path.isdir(TARGET_M):
        shutil.rmtree(TARGET_M)
    shutil.copytree(chosen, TARGET_M)
    size = sum(
        os.path.getsize(os.path.join(r, f))
        for r, _, fs in os.walk(TARGET_M) for f in fs
    )
    print(f"[export] {TARGET_M} ready, size={size / 1e6:.1f} MB", flush=True)

    # 2. 导出 l-seg（仅 benchmark，不进入正式包）。
    try:
        l_path = export("yolo26l-seg.pt", "fp16")
        if os.path.isdir("ObjectSegmenter-L.mlpackage"):
            shutil.rmtree("ObjectSegmenter-L.mlpackage")
        shutil.copytree(l_path, "ObjectSegmenter-L.mlpackage")
        print("[export] ObjectSegmenter-L.mlpackage ready (benchmark only)", flush=True)
    except Exception as e:
        print(f"[export] l-seg failed (benchmark skipped): {e}", flush=True)

    print("[export] done", flush=True)


if __name__ == "__main__":
    main()
