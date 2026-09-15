import Foundation

final class LocalStore {
    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init() {
        let fileManager = FileManager.default
        let supportDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let appDirectory = supportDirectory.appendingPathComponent("LibreCap", isDirectory: true)
        try? fileManager.createDirectory(at: appDirectory, withIntermediateDirectories: true)
        fileURL = appDirectory.appendingPathComponent("school-data.json")

        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    func load() -> CachedSchoolData {
        guard let data = try? Data(contentsOf: fileURL),
              let cached = try? decoder.decode(CachedSchoolData.self, from: data) else {
            return .empty
        }
        return cached
    }

    @discardableResult
    func save(_ data: CachedSchoolData) -> Bool {
        do {
            let encoded = try encoder.encode(data)
            try encoded.write(to: fileURL, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
