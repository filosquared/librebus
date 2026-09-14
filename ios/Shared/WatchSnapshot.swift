import Foundation

// Provider-neutral wire format. Never add credentials, cookies or API responses here.
struct WatchSnapshot: Codable, Equatable {
    static let contextKey = "schoolSnapshot"
    static let requestKey = "requestSchoolSnapshot"
    static let maxPayloadBytes = 48_000

    var version = 1
    var revision: UInt64 = 0
    var streamID = ""
    var generatedAt: Date
    var signedIn: Bool
    var accountID = ""
    var firstName = ""
    var timetableUpdatedAt: Date?
    var gradesUpdatedAt: Date?
    var homeworksUpdatedAt: Date?
    var weekStart: Date?
    var lessons: [WatchLesson] = []
    var grades: [WatchGrade] = []
    var homeworks: [WatchHomework] = []
    var isTruncated = false
    // Optional additions preserve decoding of snapshots from the first Watch release.
    var lessonAlertsEnabled: Bool? = nil
    var timetableIsComplete: Bool? = nil

    static var schoolCalendar: Calendar {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(identifier: "Europe/Warsaw")!
        return calendar
    }

    func encoded() throws -> Data {
        let data = try JSONEncoder().encode(self)
        guard data.count <= Self.maxPayloadBytes else { throw SnapshotError.tooLarge }
        return data
    }

    static func decode(_ data: Data) throws -> Self {
        guard data.count <= maxPayloadBytes else { throw SnapshotError.tooLarge }
        let snapshot = try JSONDecoder().decode(Self.self, from: data)
        guard snapshot.version == 1 else { throw SnapshotError.unsupportedVersion }
        return snapshot
    }

    func isNewer(than other: Self?) -> Bool {
        guard let other else { return true }
        return position.isNewer(than: other.position)
    }

    var position: WatchSnapshotPosition {
        WatchSnapshotPosition(streamID: streamID, revision: revision, generatedAt: generatedAt)
    }

    func covers(_ date: Date) -> Bool {
        guard signedIn, let weekStart, let end = Self.schoolCalendar.date(byAdding: .day, value: 7, to: weekStart) else { return false }
        return date >= weekStart && date < end
    }

    func lessons(on date: Date) -> [WatchLesson] {
        guard covers(date) else { return [] }
        return lessons.filter { Self.schoolCalendar.isDate($0.start, inSameDayAs: date) }
            .sorted { $0.start < $1.start }
    }

    func scheduleDays(at date: Date) -> [Date] {
        guard let weekStart else { return [] }
        let days = (0..<7).compactMap { Self.schoolCalendar.date(byAdding: .day, value: $0, to: weekStart) }
        guard let today = days.firstIndex(where: { Self.schoolCalendar.isDate($0, inSameDayAs: date) }) else { return days }
        return Array(days[today...]) + Array(days[..<today])
    }

    func nextLesson(at date: Date) -> WatchLesson? {
        guard signedIn else { return nil }
        return lessons.filter { !$0.isCancelled && $0.end > date }
            .min { $0.start < $1.start }
    }

    func upcomingHomework(at date: Date) -> [WatchHomework] {
        let today = Self.schoolCalendar.startOfDay(for: date)
        return homeworks.filter { ($0.dueDate ?? .distantFuture) >= today }
    }

    enum SnapshotError: Error { case tooLarge, unsupportedVersion }
}

// This watermark contains no school data. A new phone installation starts a new
// stream; an old queued reply must not undo a newer snapshot or a sign-out.
struct WatchSnapshotPosition: Codable, Equatable {
    var streamID: String
    var revision: UInt64
    var generatedAt: Date

    func isNewer(than other: Self) -> Bool {
        streamID == other.streamID ? revision > other.revision : generatedAt > other.generatedAt
    }
}

struct WatchLesson: Codable, Equatable, Identifiable {
    var id: String
    var subject: String
    var start: Date
    var end: Date
    var classroom: String
    var isCancelled: Bool
    var isSubstitution: Bool
    var teacher: String? = nil
}

struct WatchGrade: Codable, Equatable, Identifiable {
    var id: String
    var subject: String
    var value: String
    var category: String
    var date: String
}

struct WatchHomework: Codable, Equatable, Identifiable {
    var id: String
    var subject: String
    var type: String
    var dueDate: Date?
    var content: String
}

enum SchoolDate {
    static func parse(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = WatchSnapshot.schoolCalendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = WatchSnapshot.schoolCalendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        let dateOnly = String(value.prefix(10))
        guard let date = formatter.date(from: dateOnly), formatter.string(from: date) == dateOnly else { return nil }
        return date
    }

    static func time(_ value: String, on day: Date) -> Date? {
        let parts = value.split(separator: ":")
        guard parts.count >= 2, let hour = Int(parts[0]), let minute = Int(parts[1]),
              (0...23).contains(hour), (0...59).contains(minute) else { return nil }
        return WatchSnapshot.schoolCalendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)
    }
}
