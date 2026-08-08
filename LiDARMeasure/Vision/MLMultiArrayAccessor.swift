import CoreML
import Foundation

/// MLMultiArray 安全访问器。
///
/// 模型可能输出 Float16 / Float32 / Double，禁止直接
/// `dataPointer.bindMemory(to: Float.self)`（v0.2.0 脆弱实现）。
/// 统一按 dataType 读取，并按 strides 计算扁平索引。
enum MLMultiArrayAccessor {
    enum DataType {
        case float32
        case float16
        case double
        case other
    }

    static func dataType(of array: MLMultiArray) -> DataType {
        switch array.dataType {
        case .float32: return .float32
        case .float16: return .float16
        case .double: return .double
        default: return .other
        }
    }

    /// 按 shape 下标读取（如 [0, 42, 7]），越界返回 nil。
    static func value(_ array: MLMultiArray, indices: [Int]) -> Float? {
        guard indices.count == array.shape.count else { return nil }
        var flat = 0
        for axis in 0..<indices.count {
            let bound = Int(truncating: array.shape[axis])
            let index = indices[axis]
            guard index >= 0, index < bound else { return nil }
            flat += index * Int(truncating: array.strides[axis])
        }
        return value(atFlatIndex: flat, in: array)
    }

    static func value(atFlatIndex index: Int, in array: MLMultiArray) -> Float? {
        guard index >= 0, index < array.count else { return nil }
        let pointer = array.dataPointer
        switch dataType(of: array) {
        case .float32:
            return pointer.assumingMemoryBound(to: Float.self)[index]
        case .float16:
            return Float(pointer.assumingMemoryBound(to: Float16.self)[index])
        case .double:
            return Float(pointer.assumingMemoryBound(to: Double.self)[index])
        case .other:
            return nil
        }
    }

    /// 形状描述（供 Debug / 错误日志）。
    static func shapeDescription(of array: MLMultiArray) -> String {
        array.shape.map { $0.stringValue }.joined(separator: "x")
    }
}
