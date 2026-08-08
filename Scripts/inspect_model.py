"""打印导出模型的输入输出规格，供 Swift 端对齐。"""
import coremltools as ct

model = ct.models.MLModel("ObjectDetector.mlpackage")
spec = model.get_spec()
print("[inspect] model loaded")
for input_ in spec.description.input:
    print(f"[inspect] INPUT {input_.name} {input_.type}")
for output in spec.description.output:
    print(f"[inspect] OUTPUT {output.name} {output.type}")
print("[inspect] done")
