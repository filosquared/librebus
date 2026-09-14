// Offline checks: only synthetic fixtures; no accounts, network or simulators.
import Foundation

@main
struct WatchSnapshotChecks {
    static var checks = 0

    static func check(_ value: Bool, _ message: String) {
        precondition(value, message)
        checks += 1
    }

    static func lesson(_ id: String, at time: String, cancelled: Bool = false) -> TimetableLesson {
        TimetableLesson(id: id, lessonNumber: "1", subject: "Mathematics", isSubstitution: false,
                        isCancelled: cancelled, teacher: "Private teacher", hourFrom: time,
                        hourTo: "09:45", classroom: "12")
    }

    static func grade(_ id: String, date: String) -> GradeRecord {
        GradeRecord(id: id, subject: "Science", value: "5", weight: "1", comment: "Private comment",
                    category: "Quiz", isFinal: false, isSemester: false, semester: "1", addedDate: date,
                    teacher: "Private teacher")
    }

    static func homework(_ id: String, date: String) -> HomeworkRecord {
        HomeworkRecord(id: id, subject: "English", addedBy: "Private teacher", type: "Homework",
                       startTime: "", endTime: "", date: date, addedDate: "2026-09-14",
                       content: "Read chapter two.")
    }

    static func main() throws {
        let monday = SchoolDate.parse("2026-09-14")!
        let now = SchoolDate.time("08:00", on: monday)!
        var data = CachedSchoolData.empty
        data.profile = StudentProfile(firstName: "Fixture", lastName: "Private surname", tutorFirstName: "Private tutor",
                                      tutorLastName: "Private tutor", schoolYearStarts: "", schoolYearMiddles: "",
                                      schoolYearEnds: "", type: "Student", className: "Private class")
        data.timetable = TimetableData(nextWeek: false, days: ["Monday": [
            lesson("cancelled", at: "08:15", cancelled: true), lesson("valid", at: "09:00")
        ]], weekStart: "2026-09-14")
        data.grades = [grade("older", date: "2026-09-10"), grade("latest", date: "2026-09-14")]
        data.homeworks = [homework("past", date: "2026-09-13"), homework("today", date: "2026-09-14"),
                          homework("future", date: "2026-09-17"), homework("unknown", date: "")]
        data.messages = [MessageSummary(id: "private", sender: "Private sender", subject: "Private message", date: "")]
        data.lastSync = now
        data.timetableUpdatedAt = now
        data.gradesUpdatedAt = now
        data.homeworksUpdatedAt = now
        var snapshot = WatchSnapshotBuilder.make(from: data, signedIn: true, now: now)
        snapshot.revision = 1
        snapshot.streamID = "fixture-stream"
        snapshot.accountID = "fixture-account"
        let encoded = try snapshot.encoded()
        let decoded = try WatchSnapshot.decode(encoded)
        check(snapshot == decoded, "Wire format must round-trip")
        check(snapshot.lessons(on: now).count == 2, "Today includes cancelled lessons, visibly marked")
        check(snapshot.nextLesson(at: now)?.start == SchoolDate.time("09:00", on: monday), "Next lesson must skip cancellations")
        check(snapshot.nextLesson(at: SchoolDate.time("09:15", on: monday)!) != nil, "Keep current lesson until it ends")
        check(snapshot.nextLesson(at: SchoolDate.time("09:45", on: monday)!) == nil, "Exclude ended lessons")
        check(snapshot.grades.first?.date == "2026-09-14", "Recent grades sorted by date, not subject")
        check(snapshot.homeworks.count == 3, "Keep today's, future and unknown due dates; exclude past")
        check(snapshot.homeworks.last?.dueDate == nil, "Unknown dates remain visibly unknown")
        check(snapshot.upcomingHomework(at: SchoolDate.parse("2026-09-18")!).count == 1, "Expired homework drops out offline")
        check(!String(decoding: encoded, as: UTF8.self).contains("Private"), "No teachers, surname, class, messages or comments transferred")
        check(encoded.count <= WatchSnapshot.maxPayloadBytes, "Transport must be bounded")

        let followingMonday = SchoolDate.parse("2026-09-21")!
        check(!snapshot.covers(followingMonday), "Don't roll old timetable into a new week")
        check(snapshot.lessons(on: followingMonday).isEmpty, "Stale Monday is not today's Monday")
        check(!snapshot.covers(monday.addingTimeInterval(-1)), "A future week does not cover today")
        check(snapshot.covers(SchoolDate.parse("2026-09-20")!), "Sunday belongs to the saved week")
        let wednesday = SchoolDate.parse("2026-09-16")!
        check(snapshot.scheduleDays(at: wednesday).first == wednesday, "Timetable opens with today")
        check(Set(snapshot.scheduleDays(at: wednesday)).count == 7, "All seven dated days remain accessible")
        check(SchoolDate.parse("2026-02-30") == nil, "Reject invalid dates")
        check(SchoolDate.time("25:00", on: monday) == nil, "Reject invalid times")
        check(SchoolDate.time("8:05:00", on: monday) != nil, "Accept one-digit hours and seconds")
        let summer = SchoolDate.time("09:00", on: monday)!
        let winter = SchoolDate.time("09:00", on: SchoolDate.parse("2026-12-14")!)!
        check(WatchSnapshot.schoolCalendar.timeZone.secondsFromGMT(for: summer) == 7200, "Polish summer time")
        check(WatchSnapshot.schoolCalendar.timeZone.secondsFromGMT(for: winter) == 3600, "Polish winter time")

        data.timetable?.weekStart = "2026-12-28"
        let newYear = WatchSnapshotBuilder.make(from: data, signedIn: true, now: now)
        check(newYear.covers(SchoolDate.parse("2027-01-01")!), "Week spanning new year remains anchored")
        data.timetable?.weekStart = nil
        check(WatchSnapshotBuilder.make(from: data, signedIn: true).lessons.isEmpty, "Never guess a legacy cache's week")

        let oldTimetableDate = data.timetableUpdatedAt
        data.lastSync = now.addingTimeInterval(86400)
        check(WatchSnapshotBuilder.make(from: data, signedIn: true).timetableUpdatedAt == oldTimetableDate,
              "Failed timetable refresh must not advance its freshness timestamp")
        let legacyEncoder = JSONEncoder()
        let legacyData = try legacyEncoder.encode(data)
        var legacy = try JSONSerialization.jsonObject(with: legacyData) as! [String: Any]
        for key in ["timetableUpdatedAt", "gradesUpdatedAt", "homeworksUpdatedAt"] { legacy.removeValue(forKey: key) }
        let legacyCache = try JSONDecoder().decode(CachedSchoolData.self, from: JSONSerialization.data(withJSONObject: legacy))
        check(legacyCache.timetableUpdatedAt == nil && legacyCache.profile != nil, "Old caches must remain readable")

        var signedOut = WatchSnapshotBuilder.make(from: data, signedIn: false, now: now.addingTimeInterval(1))
        signedOut.revision = 2
        signedOut.streamID = snapshot.streamID
        check(signedOut.firstName.isEmpty && signedOut.lessons.isEmpty && signedOut.grades.isEmpty && signedOut.homeworks.isEmpty,
              "Sign-out sends only a tombstone")
        check(signedOut.isNewer(than: snapshot), "Logout supersedes school data")
        check(!snapshot.isNewer(than: signedOut), "A delayed reply must not undo logout")
        check(!snapshot.isNewer(than: snapshot), "Duplicate snapshots are idempotent")
        var reinstalled = snapshot
        reinstalled.streamID = "new-install"
        reinstalled.generatedAt = now.addingTimeInterval(60)
        check(reinstalled.isNewer(than: signedOut), "A new phone install can sync even with revision reset")
        check(!signedOut.isNewer(than: reinstalled), "Don't accept an old stream after reinstall")
        var clockChanged = snapshot
        clockChanged.revision = 3
        clockChanged.generatedAt = now.addingTimeInterval(-60)
        check(clockChanged.isNewer(than: signedOut), "Within a stream, ordering survives clock adjustment")

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("librebus-watch-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = WatchSnapshotCache(directory: directory)
        check(try cache.load() == nil, "First launch has no cached snapshot")
        try cache.save(snapshot)
        check(try cache.load() == snapshot, "Data persists for offline relaunch")
        try cache.save(signedOut)
        check(try cache.load() == signedOut, "Logout overwrites persisted personal data")

        var futureProtocol = snapshot
        futureProtocol.version = 999
        do {
            _ = try WatchSnapshot.decode(futureProtocol.encoded())
            preconditionFailure("Should reject a future wire format")
        } catch WatchSnapshot.SnapshotError.unsupportedVersion { checks += 1 }
        do {
            _ = try WatchSnapshot.decode(Data(repeating: 65, count: WatchSnapshot.maxPayloadBytes + 1))
            preconditionFailure("Should reject oversized data")
        } catch WatchSnapshot.SnapshotError.tooLarge { checks += 1 }
        do {
            _ = try WatchSnapshot.decode(Data("corrupt".utf8))
            preconditionFailure("Should reject malformed data")
        } catch { checks += 1 }

        let giant = String(repeating: "🧑🏽‍🚀\"\\\n", count: 3000)
        data.profile?.firstName = giant
        data.grades = (0..<500).map { index in
            var item = grade("\(index)", date: "2026-09-14")
            item.subject = giant; item.category = giant
            return item
        }
        data.homeworks = (0..<100).map { index in
            var item = homework("\(index)", date: "2026-09-14")
            item.content = giant; item.subject = giant
            return item
        }
        data.timetable = TimetableData(nextWeek: false, days: Dictionary(uniqueKeysWithValues:
            ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"].map { day in
                (day, (0..<25).map { index in
                    var item = lesson("\(index)", at: "09:00")
                    item.subject = giant; item.classroom = giant
                    return item
                })
            }), weekStart: "2026-09-14")
        let bounded = WatchSnapshotBuilder.make(from: data, signedIn: true, now: now)
        check(try bounded.encoded().count <= WatchSnapshot.maxPayloadBytes - 512, "Emoji and JSON escaping must fit actual byte budget")
        check(bounded.isTruncated, "Tell user when snapshot is shortened")
        check(bounded.grades.count <= 20 && bounded.homeworks.count <= 12, "Bound collection sizes")
        print("\(checks) Watch snapshot/cache checks passed (offline, synthetic data only).")
    }
}
