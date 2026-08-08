"""打印导出模型的输入输出规格，供 Swift 端对齐。"""
import sys

import coremltools as ct

path = sys.argv[1] if len(sys.argv) > 1 else "ObjectDetector.mlpackage"
model = ct.models.MLModel(path)
spec = model.get_spec()
print("[inspect] model loaded")
for input_ in spec.description.input:
    print(f"[inspect] INPUT {input_.name} {input_.type}")
for output in spec.description.output:
    print(f"[inspect] OUTPUT {output.name} {output.type}")
print("[inspect] done")
