import SwiftUI

struct WatchHomeView: View {
    @ObservedObject var store: WatchSchoolStore

    var body: some View {
        NavigationStack {
            List {
                if let snapshot = store.snapshot, snapshot.signedIn {
                    TimelineView(.periodic(from: .now, by: 60)) { context in
                        NextLessonCard(snapshot: snapshot, now: context.date)
                    }
                    .listRowBackground(Color.indigo.opacity(0.25))

                    NavigationLink { WatchTimetableView(store: store) } label: {
                        Label("Timetable", systemImage: "calendar")
                    }
                    NavigationLink { WatchGradesView(store: store) } label: {
                        Label("Recent grades", systemImage: "book.closed.fill")
                    }
                    NavigationLink { WatchHomeworkView(store: store) } label: {
                        Label("Homework", systemImage: "doc.text.fill")
                    }
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        Image(systemName: "iphone.and.arrow.forward")
                            .font(.largeTitle).foregroundStyle(.indigo)
                        Text(store.snapshot == nil ? "Your school, on your wrist" : "Signed out")
                            .font(.headline)
                        Text("Sign in to LibreCap on your paired iPhone, then refresh school data. No Watch login needed.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 6)
                }
                if store.snapshot?.lessonAlertsEnabled == true {
                    WatchLessonAlertsSection(alerts: store.lessonAlerts)
                }
                Section {
                    Button(action: store.requestLatest) {
                        Label(store.isRequesting ? "Requesting…" : "Get iPhone data", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .disabled(store.isRequesting)
                    Text(store.status).font(.footnote).foregroundStyle(.secondary)
                    if store.snapshot?.isTruncated == true {
                        Text("A shortened snapshot. Open iPhone for all details.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("LibreCap")
        }
        // Do not leave another account's details on the navigation stack.
        .id(store.snapshot?.accountID ?? "waiting")
    }
}

private struct NextLessonCard: View {
    let snapshot: WatchSnapshot
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !snapshot.firstName.isEmpty {
                Text("Hi, \(snapshot.firstName)").font(.footnote).foregroundStyle(.secondary)
            }
            if let lesson = snapshot.nextLesson(at: now) {
                Text(lesson.start <= now ? "NOW" : "UP NEXT")
                    .font(.caption.weight(.semibold)).foregroundStyle(.purple)
                Text(lesson.subject).font(.headline)
                if !WatchSnapshot.schoolCalendar.isDate(lesson.start, inSameDayAs: now) {
                    Text(lesson.start, format: .dateTime.weekday().day().month()).font(.footnote)
                }
                LessonTime(lesson: lesson)
                if !lesson.classroom.isEmpty && lesson.classroom != "—" {
                    Label("Room \(lesson.classroom)", systemImage: "door.left.hand.open")
                        .font(.footnote)
                }
                if lesson.isSubstitution { Text("Substitution").font(.footnote).foregroundStyle(.orange) }
            } else {
                Text(snapshot.covers(now) ? "No more lessons saved" : "Timetable needs a refresh")
                    .font(.headline)
                Text("Refresh on iPhone for the latest school plan.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            SnapshotAge(date: snapshot.timetableUpdatedAt, now: now)
        }
        .padding(.vertical, 6)
    }
}

struct SnapshotAge: View {
    let date: Date?
    var now: Date = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            if let date {
                Text("Updated \(date.formatted(date: .abbreviated, time: .shortened))")
                if now.timeIntervalSince(date) > 86_400 { Text("Older saved data · refresh on iPhone") }
            } else { Text("Not refreshed yet · open iPhone") }
        }
        .font(.caption2).foregroundStyle(.secondary)
    }
}

struct LessonTime: View {
    let lesson: WatchLesson

    var body: some View {
        HStack(spacing: 2) {
            Text(lesson.start, style: .time)
            Text("–")
            Text(lesson.end, style: .time)
        }
        .font(.footnote).monospacedDigit()
    }
}

#Preview("Waiting for iPhone") {
    WatchHomeView(store: WatchSchoolStore(connectsToPhone: false))
}

#Preview("School day — synthetic data") {
    let now = Date()
    let calendar = WatchSnapshot.schoolCalendar
    let week = calendar.dateInterval(of: .weekOfYear, for: now)!.start
    let lesson = WatchLesson(id: "fixture", subject: "Mathematics", start: now.addingTimeInterval(600),
                             end: now.addingTimeInterval(3300), classroom: "12", isCancelled: false, isSubstitution: false)
    let snapshot = WatchSnapshot(generatedAt: now, signedIn: true, firstName: "Alex", timetableUpdatedAt: now,
                                 gradesUpdatedAt: now, homeworksUpdatedAt: now, weekStart: week, lessons: [lesson],
                                 grades: [WatchGrade(id: "fixture", subject: "Science", value: "5", category: "Quiz", date: "2026-09-14")],
                                 homeworks: [WatchHomework(id: "fixture", subject: "English", type: "Reading", dueDate: now, content: "Read chapter two.")])
    WatchHomeView(store: WatchSchoolStore(preview: snapshot, connectsToPhone: false))
}
