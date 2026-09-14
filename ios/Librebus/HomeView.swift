import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var settings: AppSettings
    @Binding var showSettings: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    VStack(alignment: .leading, spacing: 20) {
                        HomeHeader(profile: model.data.profile, appName: settings.appName, settings: settings)

                        if let errorMessage = model.errorMessage {
                            Label(errorMessage, systemImage: "wifi.exclamationmark")
                                .font(.subheadline)
                                .foregroundStyle(.orange)
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                        }

                        TodayScheduleCard(
                            timetable: model.data.timetable,
                            now: context.date,
                            settings: settings
                        )

                        Text(settings.text(.quickActions))
                            .font(.headline)

                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                            NavigationLink { HomeworkView(filter: .assessments) } label: {
                                SummaryCard(title: settings.text(.tests), value: assessmentCount, icon: "checklist", color: .purple)
                            }
                            NavigationLink { HomeworkView(filter: .all) } label: {
                                SummaryCard(title: settings.text(.homework), value: "(model.data.homeworks.count)", icon: "doc.text.fill", color: .orange)
                            }
                            NavigationLink { MessagesView() } label: {
                                SummaryCard(title: settings.text(.messages), value: "(model.data.messages.count)", icon: "envelope.fill", color: .teal)
                            }
                            NavigationLink { AttendanceView() } label: {
                                SummaryCard(title: settings.text(.attendance), value: "(absenceCount)", icon: "calendar.badge.exclamationmark", color: .red)
                            }
                        }

                        SyncStatusCard(
                            lastSync: model.data.lastSync,
                            isSyncing: model.isSyncing,
                            automaticSyncEnabled: model.automaticSyncEnabled,
                            settings: settings,
                            sync: syncNow
                        )
                    }
                    .padding(20)
                }
            }
            .navigationTitle(settings.appName)
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button(action: syncNow) {
                        Image(systemName: "arrow.triangle.2.circlepath.circle")
                    }
                    .accessibilityLabel(settings.text(.syncNow))
                    .disabled(model.isSyncing)
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel(settings.text(.settings))
                }
            }
        }
    }

    private var assessmentCount: String {
        "\(model.data.homeworks.filter(\.isAssessment).count)"
    }

    private var absenceCount: Int {
        model.data.attendances.filter { !$0.isPresence }.count
    }

    private func syncNow() {
        Task { await model.sync() }
    }
}

private struct HomeHeader: View {
    let profile: StudentProfile?
    let appName: String
    let settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(profile == nil ? appName : settings.text(.goodToSee))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let profile {
                Text(profile.firstName)
                    .font(.largeTitle.weight(.bold))
                Text("\(settings.text(.className)) \(profile.className)")
                    .foregroundStyle(.secondary)
                if !profile.tutorName.trimmingCharacters(in: .whitespaces).isEmpty {
                    Text("\(profile.tutorName) (\(settings.text(.teacherRole)))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text(appName)
                    .font(.largeTitle.weight(.bold))
            }
        }
    }
}

private struct TodayScheduleCard: View {
    let timetable: TimetableData?
    let now: Date
    let settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(settings.text(.today))
                        .font(.headline)
                    Text(SchoolAppDate.formatted(now))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                NavigationLink(settings.text(.seeAll)) { ScheduleView() }
                    .font(.subheadline.weight(.semibold))
            }

            if let timetable,
               let dayDate = SchoolAppDate.dayDate(for: SchoolAppDate.dayKey(for: now), timetable: timetable) {
                let lessons = (timetable.days[SchoolAppDate.dayKey(for: now)] ?? []).filter { lesson in
                    guard let end = lesson.endDate(on: dayDate) else { return true }
                    return end > now
                }
                if let current = lessons.first(where: { lesson in
                    guard let start = lesson.startDate(on: dayDate), let end = lesson.endDate(on: dayDate) else { return false }
                    return start <= now && end > now
                }) {
                    CurrentLessonBanner(lesson: current, settings: settings)
                }
                ForEach(lessons.prefix(3)) { lesson in
                    NavigationLink { LessonDetailView(lesson: lesson, dayName: SchoolAppDate.dayKey(for: now)) } label: {
                        LessonRow(lesson: lesson)
                    }
                    .buttonStyle(.plain)
                }
                if lessons.isEmpty {
                    Text(settings.text(.noRemainingLessons))
                        .foregroundStyle(.secondary)
                }
            } else {
                Text(settings.text(.noLessonsToday))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.indigo.opacity(0.08), in: RoundedRectangle(cornerRadius: 18))
    }
}

private struct CurrentLessonBanner: View {
    let lesson: TimetableLesson
    let settings: AppSettings

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "play.fill")
                .foregroundStyle(.indigo)
            VStack(alignment: .leading, spacing: 2) {
                Text(settings.text(.currentLesson))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.indigo)
                Text(lesson.subject)
                    .font(.body.weight(.semibold))
            }
            Spacer()
        }
        .padding(10)
        .background(.indigo.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
    }
}

struct SummaryCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(color)
            Text(value)
                .font(.title.weight(.bold))
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        }
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
        .padding(16)
        .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 16))
        .contentShape(RoundedRectangle(cornerRadius: 16))
    }
}

private struct SyncStatusCard: View {
    let lastSync: Date?
    let isSyncing: Bool
    let automaticSyncEnabled: Bool
    let settings: AppSettings
    let sync: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Label(settings.text(.thisDevice), systemImage: "internaldrive")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                if let lastSync {
                    Text(lastSync, style: .relative)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Text(automaticSyncEnabled ? settings.text(.every45Minutes) : settings.text(.syncDescription))
                .font(.caption)
                .foregroundStyle(.secondary)
            Button(action: sync) {
                Text(isSyncing ? settings.text(.syncing) : settings.text(.syncNow))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(isSyncing)
        }
    }
}
