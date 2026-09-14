import Foundation

struct WatchSnapshotCache {
    let directory: URL
    private var file: URL { directory.appendingPathComponent("watch-snapshot.json") }

    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LibrebusWatch", isDirectory: true)
    }

    func load() throws -> WatchSnapshot? {
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        return try WatchSnapshot.decode(Data(contentsOf: file))
    }

    func save(_ snapshot: WatchSnapshot) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var excludedDirectory = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try excludedDirectory.setResourceValues(values)
        var options: Data.WritingOptions = [.atomic]
        #if os(watchOS)
        options.insert(.completeFileProtectionUntilFirstUserAuthentication)
        #endif
        try snapshot.encoded().write(to: file, options: options)
    }
}
