import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Group {
            if !model.isReady {
                ProgressView("Connecting to Librus…")
            } else if !model.isAuthenticated {
                LoginView()
            } else {
                MainTabView()
            }
        }
        .tint(.indigo)
    }
}

private struct LoginView: View {
    private enum LoginField: Hashable {
        case username
        case password
    }

    @EnvironmentObject private var model: AppModel
    @State private var username = ""
    @State private var password = ""
    @State private var isShowingPassword = false
    @FocusState private var focusedField: LoginField?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Image(systemName: "graduationcap.circle.fill")
                            .font(.system(size: 56))
                            .foregroundStyle(.indigo)
                        Text("Welcome to Librebus")
                            .font(.largeTitle.weight(.bold))
                        Text("Your school day, in one calm place.")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        Text("Librus account")
                            .font(.headline)

                        TextField("Username", text: $username)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .textFieldStyle(.roundedBorder)
                            .focused($focusedField, equals: .username)
                            .submitLabel(.next)
                            .onSubmit { focusedField = .password }

                        HStack {
                            if isShowingPassword {
                                TextField("Password", text: $password)
                                    .textFieldStyle(.roundedBorder)
                                    .focused($focusedField, equals: .password)
                                    .submitLabel(.go)
                                    .onSubmit(signIn)
                            } else {
                                SecureField("Password", text: $password)
                                    .textFieldStyle(.roundedBorder)
                                    .focused($focusedField, equals: .password)
                                    .submitLabel(.go)
                                    .onSubmit(signIn)
                            }

                            Button {
                                isShowingPassword.toggle()
                            } label: {
                                Image(systemName: isShowingPassword ? "eye.slash" : "eye")
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel(isShowingPassword ? "Hide password" : "Show password")
                        }
                    }

                    if let errorMessage = model.errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline)
                            .foregroundStyle(.red)
                    }

                    Button {
                        signIn()
                    } label: {
                        HStack {
                            if model.isSyncing { ProgressView().tint(.white) }
                            Text(model.isSyncing ? "Signing in…" : "Sign in")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(username.isEmpty || password.isEmpty || model.isSyncing)

                    Text("Your password is stored only in the iPhone's Keychain. Librebus connects directly to Librus; no separate Librebus server is required.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(24)
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationBarHidden(true)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focusedField = nil }
                }
            }
        }
    }

    private func signIn() {
        focusedField = nil
        Task {
            await model.login(username: username.trimmingCharacters(in: .whitespacesAndNewlines), password: password)
        }
    }
}

private struct MainTabView: View {
    var body: some View {
        TabView {
            DashboardView()
                .tabItem { Label("Home", systemImage: "house.fill") }
            GradesView()
                .tabItem { Label("Grades", systemImage: "book.fill") }
            ScheduleView()
                .tabItem { Label("Schedule", systemImage: "calendar") }
            AttendanceView()
                .tabItem { Label("Attendance", systemImage: "checkmark.circle") }
            MoreView()
                .tabItem { Label("More", systemImage: "ellipsis") }
        }
    }
}

private struct DashboardView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let profile = model.data.profile {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Good to see you")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text(profile.firstName)
                                .font(.largeTitle.weight(.bold))
                            Text("Class \(profile.className)")
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let errorMessage = model.errorMessage {
                        Label(errorMessage, systemImage: "wifi.exclamationmark")
                            .font(.subheadline)
                            .foregroundStyle(.orange)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                    }

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        SummaryCard(title: "Grades", value: "\(model.data.grades.count)", icon: "book.fill", color: .indigo)
                        SummaryCard(title: "Homework", value: "\(model.data.homeworks.count)", icon: "doc.text.fill", color: .orange)
                        SummaryCard(title: "Absences", value: "\(model.data.attendances.filter { !$0.isPresence }.count)", icon: "calendar.badge.exclamationmark", color: .red)
                        SummaryCard(title: "Messages", value: "\(model.data.messages.count)", icon: "envelope.fill", color: .teal)
                    }

                    if let timetable = model.data.timetable {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text(timetable.nextWeek ? "Next week" : "This week")
                                    .font(.headline)
                                Spacer()
                                NavigationLink("See all") { ScheduleView() }
                                    .font(.subheadline.weight(.semibold))
                            }
                            let todayName = currentDayName()
                            ForEach((timetable.days[todayName] ?? []).prefix(3)) { lesson in
                                LessonRow(lesson: lesson)
                            }
                            if (timetable.days[todayName] ?? []).isEmpty {
                                Text("No lessons today")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label("On this iPhone", systemImage: "internaldrive")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Spacer()
                            if let lastSync = model.data.lastSync {
                                Text(lastSync, style: .relative)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Button {
                            Task { await model.sync() }
                        } label: {
                            Label(model.isSyncing ? "Syncing…" : "Sync now", systemImage: "arrow.clockwise")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .disabled(model.isSyncing)
                    }
                }
                .padding(20)
            }
            .navigationTitle("Librebus")
        }
    }

    private func currentDayName() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEEE"
        return formatter.string(from: Date())
    }
}

private struct SummaryCard: View {
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
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct GradesView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationStack {
            Group {
                if model.data.grades.isEmpty {
                    EmptyState(title: "No grades yet", message: "Grades downloaded from Librus will appear here.", icon: "book.closed")
                } else {
                    List {
                        let grouped = Dictionary(grouping: model.data.grades, by: { $0.subject })
                        ForEach(grouped.keys.sorted(), id: \.self) { subject in
                            Section(subject) {
                                ForEach(grouped[subject] ?? []) { grade in
                                    GradeRow(grade: grade)
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Grades")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { Task { await model.sync() } } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(model.isSyncing)
                }
            }
        }
    }
}

private struct GradeRow: View {
    let grade: GradeRecord

    var body: some View {
        HStack(spacing: 14) {
            Text(grade.value)
                .font(.title3.weight(.bold))
                .frame(width: 44, height: 44)
                .background(grade.isFinal ? .indigo.opacity(0.18) : .secondary.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(grade.category)
                    .font(.body.weight(.medium))
                HStack(spacing: 6) {
                    Text(grade.weight == "none" ? "No weight" : "Weight \(grade.weight)")
                    if !grade.teacher.isEmpty { Text("· \(grade.teacher)") }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            if grade.isFinal { Image(systemName: "star.fill").foregroundStyle(.orange) }
        }
        .padding(.vertical, 4)
    }
}

private struct ScheduleView: View {
    @EnvironmentObject private var model: AppModel
    private let dayOrder = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]

    var body: some View {
        NavigationStack {
            Group {
                if let timetable = model.data.timetable, !timetable.days.isEmpty {
                    List {
                        ForEach(dayOrder.filter { timetable.days[$0] != nil }, id: \.self) { day in
                            Section(day) {
                                ForEach(timetable.days[day] ?? []) { lesson in
                                    LessonRow(lesson: lesson)
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                } else {
                    EmptyState(title: "No timetable", message: "Your timetable will appear here after the next sync.", icon: "calendar.badge.clock")
                }
            }
            .navigationTitle("Schedule")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { Task { await model.sync() } } label: { Image(systemName: "arrow.clockwise") }
                        .disabled(model.isSyncing)
                }
            }
        }
    }
}

private struct LessonRow: View {
    let lesson: TimetableLesson

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(lesson.hourFrom)
                    .font(.subheadline.weight(.semibold))
                Text(lesson.hourTo)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 48, alignment: .leading)
            Divider()
            VStack(alignment: .leading, spacing: 4) {
                Text(lesson.subject)
                    .font(.body.weight(.medium))
                    .strikethrough(lesson.isCancelled)
                Text([lesson.teacher, lesson.classroom].filter { !$0.isEmpty && $0 != "—" }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if lesson.isCancelled || lesson.isSubstitution {
                    Text(lesson.isCancelled ? "Cancelled" : "Substitution")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(lesson.isCancelled ? .red : .orange)
                }
            }
        }
        .padding(.vertical, 5)
    }
}

private struct AttendanceView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationStack {
            Group {
                if model.data.attendances.isEmpty {
                    EmptyState(title: "No attendance records", message: "Attendance downloaded from Librus will appear here.", icon: "checkmark.circle")
                } else {
                    List {
                        Section {
                            HStack {
                                AttendanceMetric(title: "Present", value: model.data.attendances.filter(\.isPresence).count, color: .green)
                                Divider()
                                AttendanceMetric(title: "Absent", value: model.data.attendances.filter { !$0.isPresence }.count, color: .red)
                            }
                            .padding(.vertical, 8)
                        }
                        Section("Recent records") {
                            ForEach(model.data.attendances) { attendance in
                                HStack(spacing: 12) {
                                    Text(attendance.shortType)
                                        .font(.subheadline.weight(.bold))
                                        .frame(width: 38, height: 38)
                                        .background((attendance.isPresence ? Color.green : Color.red).opacity(0.14), in: Circle())
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(attendance.subject).font(.body.weight(.medium))
                                        Text("\(attendance.type) · \(attendance.date)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: attendance.isPresence ? "checkmark" : "xmark")
                                        .foregroundStyle(attendance.isPresence ? .green : .red)
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Attendance")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { Task { await model.sync() } } label: { Image(systemName: "arrow.clockwise") }
                        .disabled(model.isSyncing)
                }
            }
        }
    }
}

private struct AttendanceMetric: View {
    let title: String
    let value: Int
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text("\(value)").font(.title2.weight(.bold)).foregroundStyle(color)
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct MoreView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationStack {
            List {
                if let profile = model.data.profile {
                    Section {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(profile.fullName).font(.headline)
                            Text("Class \(profile.className) · \(profile.type)").font(.subheadline).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 5)
                    }
                }
                Section("School") {
                    NavigationLink { HomeworkView() } label: { Label("Homework", systemImage: "doc.text.fill") }
                    NavigationLink { MessagesView() } label: { Label("Messages", systemImage: "envelope.fill") }
                }
                Section("Account") {
                    Button(role: .destructive) { model.logout() } label: { Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right") }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("More")
        }
    }
}

private struct HomeworkView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Group {
            if model.data.homeworks.isEmpty {
                EmptyState(title: "No homework", message: "Homework downloaded from Librus will appear here.", icon: "doc.text")
            } else {
                List {
                    ForEach(model.data.homeworks) { homework in
                        VStack(alignment: .leading, spacing: 7) {
                            HStack {
                                Text(homework.subject).font(.headline)
                                Spacer()
                                Text(homework.date).font(.caption).foregroundStyle(.secondary)
                            }
                            Text(homework.content.isEmpty ? homework.type : homework.content)
                                .font(.body)
                            if !homework.addedBy.isEmpty {
                                Text(homework.addedBy)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 6)
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("Homework")
    }
}

private struct MessagesView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Group {
            if model.data.messages.isEmpty {
                EmptyState(title: "No messages", message: "Messages downloaded from Librus will appear here.", icon: "envelope.open")
            } else {
                List(model.data.messages) { message in
                    NavigationLink {
                        MessageDetailView(summary: message)
                    } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text(message.subject).font(.body.weight(.semibold))
                                Spacer()
                                Text(message.date).font(.caption).foregroundStyle(.secondary)
                            }
                            Text(message.sender).font(.subheadline).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 5)
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("Messages")
    }
}

private struct MessageDetailView: View {
    @EnvironmentObject private var model: AppModel
    let summary: MessageSummary
    @State private var detail: MessageDetail?
    @State private var isLoading = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if isLoading {
                    ProgressView("Loading message…")
                } else if let detail {
                    Text(detail.subject).font(.title2.weight(.bold))
                    Text(detail.content.isEmpty ? "This message has no text." : detail.content)
                        .font(.body)
                        .textSelection(.enabled)
                } else {
                    EmptyState(title: "Unable to load", message: "Try syncing again and open the message once more.", icon: "envelope.badge.exclamationmark")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
        .navigationTitle(summary.subject)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            detail = await model.loadMessage(summary)
            isLoading = false
        }
    }
}

private struct EmptyState: View {
    let title: String
    let message: String
    let icon: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 42))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }
}
