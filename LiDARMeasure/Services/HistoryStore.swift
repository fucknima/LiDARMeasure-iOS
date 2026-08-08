import Combine
import Foundation

/// 测量历史：Codable + JSON 存储于 Application Support。
@MainActor
final class HistoryStore: ObservableObject {
    @Published private(set) var records: [MeasurementRecord] = []

    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(fileURL: URL? = nil) {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let folder = directory.appendingPathComponent("LiDARMeasure", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        self.fileURL = fileURL ?? folder.appendingPathComponent("history.json")
        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
        load()
    }

    func append(_ record: MeasurementRecord) {
        records.insert(record, at: 0)
        save()
        AppLog.storage.info("History appended, total=\(records.count)")
    }

    func remove(_ record: MeasurementRecord) {
        records.removeAll { $0.id == record.id }
        save()
    }

    func removeAll() {
        records.removeAll()
        save()
        AppLog.storage.info("History cleared")
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        do {
            records = try decoder.decode([MeasurementRecord].self, from: data)
            AppLog.storage.info("History loaded, count=\(records.count)")
        } catch {
            AppLog.storage.error("History load failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func save() {
        do {
            let data = try encoder.encode(records)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            AppLog.storage.error("History save failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
