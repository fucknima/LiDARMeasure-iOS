"""验证 CoreML 模型输出格式（Bug 2 任务）。

在 macOS 上运行：加载 mlpackage，用 fixture 图推理，打印：
- output names / shapes
- raw 输出数值范围（min / max / mean）
- 前 N 个有效检测的 box/class 原始值

用于确认 cx/cy/w/h 是 0~1 归一化还是 0~640 像素值，
以及类别分数所在通道与偏移。Swift decoder 必须依据真实输出实现。
"""
import sys

import coremltools as ct
from PIL import Image

MODEL_PATH = sys.argv[1] if len(sys.argv) > 1 else "ObjectSegmenter.mlpackage"
IMAGE_PATH = sys.argv[2] if len(sys.argv) > 2 else "Tests/Fixtures/coco_bus.jpg"


def main():
    print(f"[check] loading model: {MODEL_PATH}")
    model = ct.models.MLModel(MODEL_PATH)
    spec = model.get_spec()
    for inp in spec.description.input:
        print(f"[check] INPUT  {inp.name} {inp.type}")
    for out in spec.description.output:
        print(f"[check] OUTPUT {out.name} {out.type}")

    print(f"[check] loading image: {IMAGE_PATH}")
    image = Image.open(IMAGE_PATH).convert("RGB").resize((640, 640))
    print(f"[check] image size: {image.size}")

    # 按 spec 构造输入：image 输入需要 dict(name: image)。
    input_name = spec.description.input[0].name
    outputs = model.predict({input_name: image})
    print(f"[check] predict done, {len(outputs)} outputs")

    import numpy as np

    for name, value in outputs.items():
        arr = np.asarray(value)
        print(f"[check] {name}: shape={arr.shape} dtype={arr.dtype}")
        print(f"        min={arr.min():.4f} max={arr.max():.4f} mean={arr.mean():.4f}")

    # 分析第一个 multiArray 输出（通常是检测头 raw tensor）。
    det_key = next(k for k, v in outputs.items() if getattr(v, "ndim", 0) >= 2)
    det = np.asarray(outputs[det_key])
    if det.ndim == 3:
        channels, anchors = det.shape[1], det.shape[2]
        print(f"[check] detection head: {channels} channels x {anchors} anchors")
        cx = det[0, 0, :]
        cy = det[0, 1, :]
        w = det[0, 2, :]
        h = det[0, 3, :]
        print(f"[check] cx: min={cx.min():.4f} max={cx.max():.4f} mean={cx.mean():.4f}")
        print(f"[check] cy: min={cy.min():.4f} max={cy.max():.4f} mean={cy.mean():.4f}")
        print(f"[check] w : min={w.min():.4f} max={w.max():.4f} mean={w.mean():.4f}")
        print(f"[check] h : min={h.min():.4f} max={h.max():.4f} mean={h.mean():.4f}")
        # 类别分数范围。
        class_scores = det[0, 4:, :]
        print(f"[check] class scores: min={class_scores.min():.4f} max={class_scores.max():.4f}")
        # 前 N 个最高分 anchor。
        top = np.argsort(class_scores.max(axis=0))[-5:][::-1]
        for a in top:
            best = class_scores[:, a].argmax()
            print(
                f"[check] anchor {a}: class={best} score={class_scores[best, a]:.4f} "
                f"cx={cx[a]:.4f} cy={cy[a]:.4f} w={w[a]:.4f} h={h[a]:.4f}"
            )
        print("[check] done")
    else:
        print("[check] WARNING: unexpected detection head rank:", det.ndim)


if __name__ == "__main__":
    main()
