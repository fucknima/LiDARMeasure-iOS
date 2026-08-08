import Foundation
import OSLog

enum AppLog {
    static let app = Logger(subsystem: "com.lidarmeasure.app", category: "App")
    static let ar = Logger(subsystem: "com.lidarmeasure.app", category: "AR")
    static let depth = Logger(subsystem: "com.lidarmeasure.app", category: "Depth")
    static let vision = Logger(subsystem: "com.lidarmeasure.app", category: "Vision")
    static let geometry = Logger(subsystem: "com.lidarmeasure.app", category: "Geometry")
    static let measure = Logger(subsystem: "com.lidarmeasure.app", category: "Measure")
    static let roomPlan = Logger(subsystem: "com.lidarmeasure.app", category: "RoomPlan")
    static let storage = Logger(subsystem: "com.lidarmeasure.app", category: "Storage")
}
