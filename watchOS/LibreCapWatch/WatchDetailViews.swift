import SwiftUI

struct WatchTimetableView: View {
    @ObservedObject var store: WatchSchoolStore

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            List {
                if let snapshot = store.snapshot, snapshot.weekStart != nil {
                    Section {
                        SnapshotAge(date: snapshot.timetableUpdatedAt, now: context.date)
                        Text("School time · Warsaw").font(.caption2).foregroundStyle(.secondary)
                    }
                    ForEach(snapshot.scheduleDays(at: context.date), id: \.self) { day in
                        Section {
                            let lessons = snapshot.lessons(on: day)
                            if lessons.isEmpty { Text("No lessons saved").font(.footnote).foregroundStyle(.secondary) }
                            ForEach(lessons) { lesson in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(lesson.subject).font(.headline).strikethrough(lesson.isCancelled)
                                    LessonTime(lesson: lesson)
                                    if !lesson.classroom.isEmpty && lesson.classroom != "—" {
                                        Text("Room \(lesson.classroom)").font(.footnote).foregroundStyle(.secondary)
                                    }
                                    if lesson.isCancelled { Text("Cancelled").font(.footnote).foregroundStyle(.red) }
                                    else if lesson.isSubstitution { Text("Substitution").font(.footnote).foregroundStyle(.orange) }
                                }
                            }
                        } header: {
                            Text(day, format: .dateTime.weekday().day().month())
                        }
                    }
                } else { Text("Refresh the timetable in LibreCap on your iPhone.") }
            }
        }
        .navigationTitle("Timetable")
    }
}

struct WatchGradesView: View {
    @ObservedObject var store: WatchSchoolStore

    var body: some View {
        List {
            SnapshotAge(date: store.snapshot?.gradesUpdatedAt)
            if store.snapshot?.grades.isEmpty != false {
                Text("No grades saved yet.").foregroundStyle(.secondary)
            }
            ForEach(store.snapshot?.grades ?? []) { grade in
                VStack(alignment: .leading, spacing: 5) {
                    Text(grade.value).font(.title2.bold()).foregroundStyle(.indigo)
                    Text(grade.subject).font(.headline)
                    Text(grade.category).font(.footnote)
                    Text(grade.date).font(.caption2).foregroundStyle(.secondary)
                }
                .padding(.vertical, 3)
            }
        }
        .navigationTitle("Grades")
    }
}

struct WatchHomeworkView: View {
    @ObservedObject var store: WatchSchoolStore

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            List {
                SnapshotAge(date: store.snapshot?.homeworksUpdatedAt, now: context.date)
                let homeworks = store.snapshot?.upcomingHomework(at: context.date) ?? []
                if homeworks.isEmpty { Text("No upcoming homework saved.").foregroundStyle(.secondary) }
                ForEach(homeworks) { homework in
                    NavigationLink {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 10) {
                                Text(homework.subject).font(.headline)
                                HomeworkDueDate(homework: homework)
                                Text(homework.content.isEmpty ? homework.type : homework.content)
                                Text("Open iPhone for full details.").font(.footnote).foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal)
                        }
                        .navigationTitle("Homework")
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(homework.subject).font(.headline)
                            Text(homework.type).font(.footnote)
                            HomeworkDueDate(homework: homework)
                        }
                    }
                }
            }
        }
        .navigationTitle("Homework")
    }
}

private struct HomeworkDueDate: View {
    let homework: WatchHomework

    var body: some View {
        Group {
            if let date = homework.dueDate {
                Text(date, format: .dateTime.weekday().day().month())
            } else { Text("Due date unavailable") }
        }
        .font(.footnote).foregroundStyle(.secondary)
    }
}
