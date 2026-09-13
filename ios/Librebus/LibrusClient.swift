import Foundation
import OSLog

enum LibrusClientError: LocalizedError {
    case invalidCredentials
    case unavailable
    case unexpectedResponse
    case malformedData

    var errorDescription: String? {
        switch self {
        case .invalidCredentials:
            return "Librus rejected the login details."
        case .unavailable:
            return "Librus is currently unavailable. Check your internet connection."
        case .unexpectedResponse, .malformedData:
            return "Librus returned data the app could not read."
        }
    }
}

final class LibrusClient {
    private let apiBase = URL(string: "https://synergia.librus.pl/gateway/api/2.0/")!
    private let portalBase = URL(string: "https://synergia.librus.pl")!
    private let oauthBase = URL(string: "https://api.librus.pl/OAuth/")!
    private let logger = Logger(subsystem: "com.filiplopes.Librebus", category: "network")
    private let cookieStorage: HTTPCookieStorage
    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 60
        configuration.waitsForConnectivity = true
        configuration.httpShouldSetCookies = true
        configuration.httpCookieAcceptPolicy = .always
        let cookieStorage = HTTPCookieStorage()
        configuration.httpCookieStorage = cookieStorage
        self.cookieStorage = cookieStorage
        session = URLSession(configuration: configuration)
    }

    func login(username: String, password: String) async throws -> StudentProfile {
        do {
            _ = try await request(url: oauthURL(path: "Authorization?client_id=46&response_type=code&scope=mydata"))

			let loginURL = oauthURL(path: "Authorization?client_id=46")
			let loginBody = formBody([
				"action": "login",
				"login": username,
				"pass": password
			])
			let (_, loginResponse) = try await request(
				url: loginURL,
				method: "POST",
				body: loginBody,
				headers: ["Content-Type": "application/x-www-form-urlencoded"]
			)
			guard (200..<400).contains(loginResponse.statusCode) else {
                throw LibrusClientError.invalidCredentials
            }

			let grantURL = oauthURL(path: "Authorization/Grant?client_id=46")
			let (_, grantResponse) = try await request(url: grantURL)
			guard (200..<400).contains(grantResponse.statusCode) else {
				throw LibrusClientError.invalidCredentials
			}
			bridgeGrantCookies(to: apiBase)
			bridgeGrantCookies(to: portalBase)

			let tokenInfo = try await apiJSON("Auth/TokenInfo")
			let identifier = string(tokenInfo["UserIdentifier"], fallback: "")
			guard !identifier.isEmpty else {
				throw LibrusClientError.invalidCredentials
			}
			let (_, accessResponse) = try await request(url: URL(string: "Auth/UserInfo/\(identifier)", relativeTo: apiBase)!.absoluteURL)
			guard accessResponse.statusCode == 200 else {
				throw LibrusClientError.invalidCredentials
			}
			return try await fetchProfile()
        } catch let error as LibrusClientError {
            throw error
        } catch {
            throw LibrusClientError.unavailable
        }
    }

    func fetchProfile() async throws -> StudentProfile {
        async let meTask = apiJSON("Me")
        async let profileTask = apiJSON("UserProfile")
        async let usersTask = apiJSON("Users")
        async let classesTask = apiJSON("Classes")

        let me = try await meTask
        let userProfile = try await profileTask
        let users = try await usersTask
        let classes = try await classesTask

        let account = dictionary(me["Me"])?["Account"].flatMap(dictionary) ?? [:]
        let schoolClass = dictionary(classes["Class"]) ?? [:]
        let tutorID = identifier(dictionary(schoolClass["ClassTutor"])?["Id"])
        let tutor = userMap(users)[tutorID] ?? [:]

        let number = string(schoolClass["Number"], fallback: "")
        let symbol = string(schoolClass["Symbol"], fallback: "").uppercased()
        let className = [number, symbol].filter { !$0.isEmpty }.joined(separator: " ")

        return StudentProfile(
            firstName: string(account["FirstName"], fallback: "Student"),
            lastName: string(account["LastName"], fallback: ""),
            tutorFirstName: string(tutor["FirstName"], fallback: ""),
            tutorLastName: string(tutor["LastName"], fallback: ""),
            schoolYearStarts: string(schoolClass["BeginSchoolYear"], fallback: ""),
            schoolYearMiddles: string(schoolClass["EndFirstSemester"], fallback: ""),
            schoolYearEnds: string(schoolClass["EndSchoolYear"], fallback: ""),
            type: string(dictionary(userProfile["UserProfile"])?["UnitType"], fallback: "Student").capitalized,
            className: className.isEmpty ? "Class" : className
        )
    }

    func fetchGrades() async throws -> [GradeRecord] {
        async let responseTask = apiJSON("Grades")
        async let categoriesTask = apiJSON("Grades/Categories")
        async let commentsTask = apiJSON("Grades/Comments")
        async let subjectsTask = apiJSON("Subjects")
        async let teachersTask = apiJSON("Users")

        let response = try await responseTask
        let categories = gradeCategories(try await categoriesTask)
        let comments = commentMap(try await commentsTask)
        let subjects = subjectMap(try await subjectsTask)
        let teachers = userMap(try await teachersTask)

        let rawGrades = array(response["Grades"])
        return rawGrades.enumerated().map { index, raw in
            let subjectID = identifier(dictionary(raw["Subject"])?["Id"])
            let categoryID = identifier(dictionary(raw["Category"])?["Id"])
            let addedByID = identifier(dictionary(raw["AddedBy"])?["Id"])
            let subject = subjects[subjectID] ?? "Subject"
            let category = categories[categoryID] ?? (name: "Grade", weight: "none")
            let teacher = teachers[addedByID] ?? [:]
            let commentID = identifier(dictionary(array(raw["Comments"]).first)?["Id"])
            let value = string(raw["Grade"], fallback: "—")
            let addedDate = string(raw["AddDate"], fallback: "")

            return GradeRecord(
                id: identifier(raw["Id"]).isEmpty ? "\(subject)-\(addedDate)-\(value)-\(index)" : identifier(raw["Id"]),
                subject: subject,
                value: value,
                weight: category.weight,
                comment: comments[commentID] ?? "",
                category: category.name,
                isFinal: boolean(raw["IsFinal"]) || boolean(raw["IsFinalProposition"]),
                isSemester: boolean(raw["IsSemester"]) || boolean(raw["IsSemesterProposition"]),
                semester: string(raw["Semester"], fallback: ""),
                addedDate: addedDate,
                teacher: teacherName(teacher)
            )
        }
        .sorted { $0.subject.localizedCaseInsensitiveCompare($1.subject) == .orderedAscending }
    }

    func fetchTimetable() async throws -> TimetableData {
        let calendar = Calendar(identifier: .iso8601)
        let today = Date()
        let pivot = calendar.date(byAdding: .day, value: 2, to: today) ?? today
        let weekday = calendar.component(.weekday, from: pivot)
        let daysFromMonday = (weekday + 5) % 7
        let weekStart = calendar.date(byAdding: .day, value: -daysFromMonday, to: pivot) ?? pivot
        let weekEnd = calendar.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart
        let dateFrom = dateString(weekStart)
        let dateTo = dateString(weekEnd)

        async let timetableTask = apiJSON("Timetables?weekStart=\(dateFrom)")
        async let activitiesTask = apiJSON("Timetables/OtherActivitiesRegister?dateFrom=\(dateFrom)&dateTo=\(dateTo)&hideOutdatedEntries=false")
        async let classroomsTask = apiJSON("TimetableEntries")

        let timetableResponse = try await timetableTask
        let activitiesResponse = try await activitiesTask
        let classrooms = classroomMap(try await classroomsTask)
        var lessonsByDay: [String: [TimetableLesson]] = [:]
        let dayNames = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
        var lessonByStart: [String: String] = [:]

        if let timetable = timetableResponse["Timetable"] as? [String: Any] {
            for (date, rawDay) in timetable {
				guard let dateValue = parseDate(date),
					  let dayName = dayName(for: dateValue, calendar: calendar, names: dayNames) else {
                    continue
                }
                guard let entryLists = rawDay as? [[Any]] else { continue }
                for (index, rawEntry) in entryLists.enumerated() {
                    guard let lesson = dictionary(rawEntry.first) else { continue }
                    let hourFrom = string(lesson["HourFrom"], fallback: "")
                    let lessonNumber = string(lesson["LessonNo"], fallback: "-")
                    lessonByStart[hourFrom] = lessonNumber
                    let classroomID = identifier(dictionary(lesson["Classroom"])?["Id"])
                    let teacher = dictionary(lesson["Teacher"]) ?? [:]
                    let subject = string(dictionary(lesson["Subject"])?["Name"], fallback: "Lesson")
                    lessonsByDay[dayName, default: []].append(TimetableLesson(
                        id: "\(date)-\(lessonNumber)-\(index)",
                        lessonNumber: lessonNumber,
                        subject: subject,
                        isSubstitution: boolean(lesson["IsSubstitutionClass"]),
                        isCancelled: boolean(lesson["IsCanceled"]),
                        teacher: teacherName(teacher),
                        hourFrom: hourFrom,
                        hourTo: string(lesson["HourTo"], fallback: ""),
                        classroom: classrooms[classroomID] ?? "—"
                    ))
                }
            }
        }

        if let activities = activitiesResponse["data"] as? [[String: Any]] {
            for (index, item) in activities.enumerated() {
                let date = string(item["date"], fallback: "")
				guard let dateValue = parseDate(date),
					  let dayName = dayName(for: dateValue, calendar: calendar, names: dayNames) else {
                    continue
                }
                let teacherParts = string(item["teacherName"], fallback: "").split(separator: " ").map(String.init)
                let classroom = dictionary(item["classroom"])
                let start = string(item["startTime"], fallback: "")
                lessonsByDay[dayName, default: []].append(TimetableLesson(
                    id: "activity-\(date)-\(index)",
                    lessonNumber: lessonByStart[start] ?? "-",
                    subject: string(item["title"], fallback: "Activity"),
                    isSubstitution: false,
                    isCancelled: false,
                    teacher: teacherParts.count > 1 ? teacherParts.dropFirst().joined(separator: " ") + " " + teacherParts[0] : teacherParts.first ?? "—",
                    hourFrom: start,
                    hourTo: string(item["endTime"], fallback: ""),
                    classroom: string(classroom?["symbol"], fallback: "—")
                ))
            }
        }

        for day in lessonsByDay.keys {
            lessonsByDay[day]?.sort { $0.hourFrom < $1.hourFrom }
        }

        return TimetableData(
            nextWeek: calendar.component(.weekOfYear, from: today) < calendar.component(.weekOfYear, from: weekStart),
            days: lessonsByDay
        )
    }

    func fetchAttendances() async throws -> [AttendanceRecord] {
        async let attendancesTask = apiJSON("Attendances")
        async let teachersTask = apiJSON("Users")
        async let lessonsTask = apiJSON("Lessons")
        async let subjectsTask = apiJSON("Subjects")
        async let typesTask = apiJSON("Attendances/Types")

        let attendances = try await attendancesTask
        let teachers = userMap(try await teachersTask)
        let lessons = lessonSubjectMap(try await lessonsTask)
        let subjects = subjectMap(try await subjectsTask)
        let types = attendanceTypeMap(try await typesTask)

		let records = array(attendances["Attendances"]).enumerated().map { index, raw in
            let lessonID = identifier(dictionary(raw["Lesson"])?["Id"])
            let typeID = identifier(dictionary(raw["Type"])?["Id"])
            let addedByID = identifier(dictionary(raw["AddedBy"])?["Id"])
            let type = types[typeID] ?? (name: "Attendance", short: "?", isPresence: false)
            return AttendanceRecord(
                id: identifier(raw["Id"]).isEmpty ? "attendance-\(index)" : identifier(raw["Id"]),
                subject: subjects[lessons[lessonID] ?? ""] ?? "Lesson",
                type: type.name,
                shortType: type.short,
                isPresence: type.isPresence,
                addedDate: string(raw["AddDate"], fallback: ""),
                date: string(raw["Date"], fallback: ""),
                teacher: teacherName(teachers[addedByID] ?? [:])
            )
		}
		return Array(records.reversed())
    }

    func fetchHomeworks() async throws -> [HomeworkRecord] {
        async let homeworksTask = apiJSON("HomeWorks")
        async let teachersTask = apiJSON("Users")
        async let categoriesTask = apiJSON("HomeWorks/Categories")
        async let subjectsTask = apiJSON("Subjects")

        let homeworks = try await homeworksTask
        let teachers = userMap(try await teachersTask)
        let categories = homeworkCategoryMap(try await categoriesTask)
        let subjects = subjectMap(try await subjectsTask)

		let records = array(homeworks["HomeWorks"]).enumerated().map { index, raw in
            let subjectID = identifier(dictionary(raw["Subject"])?["Id"])
            let teacherID = identifier(dictionary(raw["CreatedBy"])?["Id"])
            let categoryID = identifier(dictionary(raw["Category"])?["Id"])
            return HomeworkRecord(
                id: identifier(raw["Id"]).isEmpty ? "homework-\(index)" : identifier(raw["Id"]),
                subject: subjects[subjectID] ?? "Lesson \(string(raw["LessonNo"], fallback: "") )",
                addedBy: teacherName(teachers[teacherID] ?? [:]),
                type: categories[categoryID] ?? "Homework",
                startTime: string(raw["TimeFrom"], fallback: ""),
                endTime: string(raw["TimeTo"], fallback: ""),
                date: string(raw["Date"], fallback: ""),
                addedDate: string(raw["AddDate"], fallback: ""),
                content: string(raw["Content"], fallback: "")
            )
		}
		return Array(records.reversed())
    }

    func fetchMessages() async throws -> [MessageSummary] {
        let html = try await portalHTML(path: "/wiadomosci")
        let rows = allCaptures(#"<tr[^>]*>(.*?)</tr>"#, in: html)
        return rows.compactMap { row in
            let columns = allCaptures(#"<td[^>]*>(.*?)</td>"#, in: row)
            guard columns.count > 4 else { return nil }
            guard let href = capture(#"href=["']([^"']+)["']"#, in: columns[2]) else { return nil }
            let id = messageID(from: href)
            guard !id.isEmpty else { return nil }
            let senderText = htmlText(columns[2])
            let sender = senderText.components(separatedBy: "(").first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? senderText
            return MessageSummary(
                id: id,
                sender: sender,
                subject: htmlText(columns[3]),
                date: htmlText(columns[4])
            )
        }
    }

    func fetchMessage(id: String) async throws -> MessageDetail {
        let path = "/wiadomosci/\(id.replacingOccurrences(of: "-", with: "/"))"
        let html = try await portalHTML(path: path)
        let content = capture(#"<div[^>]*class=["'][^"']*container-message-content[^"']*["'][^>]*>(.*?)</div>"#, in: html) ?? ""
        let subject = htmlText(capture(#"<table[^>]*class=["'][^"']*stretch[^"']*["'][^>]*>.*?<td[^>]*>(.*?)</td>"#, in: html) ?? "")
        return MessageDetail(
            subject: subject.isEmpty ? "Message" : subject,
            sender: "",
            date: "",
            content: htmlText(content)
        )
    }

    private func apiJSON(_ path: String) async throws -> [String: Any] {
		let url = URL(string: path, relativeTo: apiBase)!.absoluteURL
        let (data, response) = try await request(url: url)
        guard response.statusCode == 200 else {
            if response.statusCode == 401 { throw LibrusClientError.invalidCredentials }
            throw LibrusClientError.unexpectedResponse
        }
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let result = object as? [String: Any] else {
            throw LibrusClientError.malformedData
        }
        return result
    }

    private func portalHTML(path: String) async throws -> String {
        let url = portalBase.appendingPathComponent(path)
        let (data, response) = try await request(url: url)
        guard response.statusCode == 200, let html = String(data: data, encoding: .utf8) else {
            throw LibrusClientError.unexpectedResponse
        }
        return html
    }

	private func request(url: URL, method: String = "GET", body: Data? = nil, headers: [String: String] = [:]) async throws -> (Data, HTTPURLResponse) {
		for attempt in 0..<3 {
			var request = URLRequest(url: url)
			request.httpMethod = method
			request.httpBody = body
			for (key, value) in headers {
				request.setValue(value, forHTTPHeaderField: key)
			}

			do {
				let (data, response) = try await session.data(for: request)
				guard let httpResponse = response as? HTTPURLResponse else {
					throw LibrusClientError.unexpectedResponse
				}
				logger.debug("Librus request \(method, privacy: .public) \(url.host ?? "unknown", privacy: .public) returned \(httpResponse.statusCode, privacy: .public)")
				return (data, httpResponse)
			} catch let error as LibrusClientError {
				throw error
			} catch {
				logger.error("Librus request failed for \(url.host ?? "unknown", privacy: .public): \(error.localizedDescription, privacy: .public)")
				if attempt == 2 {
					throw LibrusClientError.unavailable
				}
				try? await Task.sleep(nanoseconds: UInt64(250_000_000 * (attempt + 1)))
			}
		}
		throw LibrusClientError.unavailable
	}

    private func oauthURL(path: String) -> URL {
        URL(string: path, relativeTo: oauthBase)!.absoluteURL
    }

    private func formBody(_ values: [String: String]) -> Data? {
        var components = URLComponents()
        components.queryItems = values.map { URLQueryItem(name: $0.key, value: $0.value) }
        return components.percentEncodedQuery?.data(using: .utf8)
    }

	private func bridgeGrantCookies(to destination: URL) {
		guard let destinationHost = destination.host else { return }
		let grantURL = oauthBase
		for cookie in cookieStorage.cookies(for: grantURL) ?? [] {
			var properties: [HTTPCookiePropertyKey: Any] = [
				.name: cookie.name,
				.value: cookie.value,
				.domain: destinationHost,
				.path: "/"
			]
			if cookie.isSecure { properties[.secure] = "TRUE" }
			if let expires = cookie.expiresDate { properties[.expires] = expires }
			if let bridged = HTTPCookie(properties: properties) {
				cookieStorage.setCookie(bridged)
			}
		}
	}

    private func dictionary(_ value: Any?) -> [String: Any]? {
        value as? [String: Any]
    }

    private func array(_ value: Any?) -> [[String: Any]] {
        value as? [[String: Any]] ?? []
    }

    private func identifier(_ value: Any?) -> String {
        if let value = value as? String { return value }
        if let value = value as? NSNumber { return value.stringValue }
        return ""
    }

    private func string(_ value: Any?, fallback: String) -> String {
        if let value = value as? String { return value }
        if let value = value as? NSNumber { return value.stringValue }
        return fallback
    }

    private func boolean(_ value: Any?) -> Bool {
        if let value = value as? Bool { return value }
        if let value = value as? NSNumber { return value.boolValue }
        return false
    }

    private func userMap(_ object: [String: Any]) -> [String: [String: Any]] {
        var result: [String: [String: Any]] = [:]
        for user in array(object["Users"]) {
            result[identifier(user["Id"])] = user
        }
        return result
    }

    private func subjectMap(_ object: [String: Any]) -> [String: String] {
        Dictionary(uniqueKeysWithValues: array(object["Subjects"]).map {
            (identifier($0["Id"]), string($0["Name"], fallback: "Subject"))
        })
    }

    private func gradeCategories(_ object: [String: Any]) -> [String: (name: String, weight: String)] {
        var result: [String: (name: String, weight: String)] = [:]
        for category in array(object["Categories"]) {
            result[identifier(category["Id"])] = (
                string(category["Name"], fallback: "Grade"),
                string(category["Weight"], fallback: "none")
            )
        }
        return result
    }

    private func homeworkCategoryMap(_ object: [String: Any]) -> [String: String] {
        Dictionary(uniqueKeysWithValues: array(object["Categories"]).map {
            (identifier($0["Id"]), string($0["Name"], fallback: "Homework"))
        })
    }

    private func commentMap(_ object: [String: Any]) -> [String: String] {
        Dictionary(uniqueKeysWithValues: array(object["Comments"]).map {
            (identifier($0["Id"]), string($0["Text"], fallback: ""))
        })
    }

    private func lessonSubjectMap(_ object: [String: Any]) -> [String: String] {
        var result: [String: String] = [:]
        for lesson in array(object["Lessons"]) {
            result[identifier(lesson["Id"])] = identifier(dictionary(lesson["Subject"])?["Id"])
        }
        return result
    }

    private func attendanceTypeMap(_ object: [String: Any]) -> [String: (name: String, short: String, isPresence: Bool)] {
        var result: [String: (name: String, short: String, isPresence: Bool)] = [:]
        for type in array(object["Types"]) {
            result[identifier(type["Id"])] = (
                string(type["Name"], fallback: "Attendance"),
                string(type["Short"], fallback: "?"),
                boolean(type["IsPresenceKind"])
            )
        }
        return result
    }

    private func classroomMap(_ object: [String: Any]) -> [String: String] {
        var result: [String: String] = [:]
        for entry in array(object["TimetableEntries"]) {
            if let classroom = dictionary(entry["Classroom"]) {
                result[identifier(classroom["Id"])] = string(classroom["Symbol"] ?? classroom["Name"], fallback: "—")
            }
        }
        return result
    }

    private func teacherName(_ teacher: [String: Any]) -> String {
        let first = string(teacher["FirstName"], fallback: "")
        let last = string(teacher["LastName"], fallback: "")
        return [first, last].filter { !$0.isEmpty }.joined(separator: " ")
    }

    private func dateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .iso8601)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

	private func parseDate(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .iso8601)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
		return formatter.date(from: value)
	}

	private func dayName(for date: Date, calendar: Calendar, names: [String]) -> String? {
		let weekday = calendar.component(.weekday, from: date)
		return names[safe: (weekday + 5) % 7]
	}

    private func messageID(from href: String) -> String {
        var path = href
        if path.hasPrefix("/") { path.removeFirst() }
        if let range = path.range(of: "wiadomosci/") {
            path = String(path[range.upperBound...])
        }
        return path.split(separator: "?").first.map(String.init)?.replacingOccurrences(of: "/", with: "-") ?? ""
    }

    private func capture(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range), match.numberOfRanges > 1,
              let captureRange = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[captureRange])
    }

    private func allCaptures(_ pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard match.numberOfRanges > 1, let captureRange = Range(match.range(at: 1), in: text) else { return nil }
            return String(text[captureRange])
        }
    }

    private func htmlText(_ html: String) -> String {
        let withoutScripts = html.replacingOccurrences(of: #"<script[^>]*>.*?</script>"#, with: "", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"<style[^>]*>.*?</style>"#, with: "", options: [.regularExpression, .caseInsensitive])
        if let data = withoutScripts.data(using: .utf8),
           let attributed = try? NSAttributedString(
               data: data,
               options: [
                   .documentType: NSAttributedString.DocumentType.html,
                   .characterEncoding: String.Encoding.utf8.rawValue
               ],
               documentAttributes: nil
           ) {
            return attributed.string.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return withoutScripts.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
