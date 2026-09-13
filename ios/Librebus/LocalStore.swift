import Foundation

final class LocalStore {
    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init() {
        let fileManager = FileManager.default
        let supportDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let appDirectory = supportDirectory.appendingPathComponent("Librebus", isDirectory: true)
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

    func save(_ data: CachedSchoolData) {
        guard let encoded = try? encoder.encode(data) else {
            return
        }
        try? encoded.write(to: fileURL, options: .atomic)
    }

    func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
