"""CoreML 分割模型 smoke test（CI 必须通过）。

- 加载 ObjectSegmenter.mlpackage
- 用 fixture 图（coco_bus.jpg / coco_person.jpg）推理
- 确认：至少产生 1 个检测 candidate + mask prototype tensor 非空
- 0 检测 → 非零退出（CI 失败）
"""
import sys

import coremltools as ct
from PIL import Image

MODEL_PATH = sys.argv[1] if len(sys.argv) > 1 else "ObjectSegmenter.mlpackage"
FIXTURES = [
    "Tests/Fixtures/coco_bus.jpg",
    "Tests/Fixtures/coco_person.jpg",
]


def main():
    import numpy as np

    print(f"[smoke] loading model: {MODEL_PATH}")
    model = ct.models.MLModel(MODEL_PATH)
    spec = model.get_spec()
    input_name = spec.description.input[0].name
    output_names = [o.name for o in spec.description.output]
    print(f"[smoke] inputs: {input_name}")

    total_detections = 0
    for fixture in FIXTURES:
        print(f"[smoke] infer: {fixture}")
        image = Image.open(fixture).convert("RGB").resize((640, 640))
        out = model.predict({input_name: image})

        det_key = None
        proto_key = None
        for name in output_names:
            arr = getattr(out[name], "shape", None)
            print(f"[smoke]   {name}: {arr}")
            if arr is not None and len(arr) == 3:
                det_key = name
            if arr is not None and len(arr) == 4 and arr[1] == 32:
                proto_key = name

        if det_key is None:
            print("[smoke] FAIL: no 3D detection tensor found")
            sys.exit(1)
        det = np.asarray(out[det_key])
        confs = det[0, :, 4]
        n = int((confs > 0.3).sum())
        total_detections += n
        print(f"[smoke]   detections(conf>0.3): {n}, max_conf={confs.max():.3f}")

        if proto_key is None:
            print("[smoke] FAIL: mask prototype tensor not found")
            sys.exit(1)
        proto = np.asarray(out[proto_key])
        print(f"[smoke]   proto shape={proto.shape} nonzero={np.count_nonzero(proto)}")

    if total_detections == 0:
        print("[smoke] FAIL: zero detections across fixtures")
        sys.exit(1)

    print(f"[smoke] PASS: {total_detections} detections, prototypes present")


if __name__ == "__main__":
    main()
