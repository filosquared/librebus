import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        Group {
            if !model.isReady {
                ProgressView(settings.text(.connecting))
            } else if !model.isAuthenticated {
                LoginView()
            } else {
                MainTabView()
            }
        }
        .tint(.indigo)
        .preferredColorScheme(settings.appearance.colorScheme)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .environmentObject(model)
        .environmentObject(settings)
    }
}

private struct LoginView: View {
    private enum LoginField: Hashable {
        case username
        case password
    }

    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var settings: AppSettings
    @State private var username = ""
    @State private var password = ""
    @FocusState private var focusedField: LoginField?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Image(systemName: "graduationcap.circle.fill")
                            .font(.system(size: 56))
                            .foregroundStyle(.indigo)
                        Text(settings.text(.welcome))
                            .font(.largeTitle.weight(.bold))
                        Text(settings.text(.tagline))
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        Text(settings.text(.schoolAccount))
                            .font(.headline)
                        Text(settings.text(.loginHint))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        TextField(settings.text(.schoolLogin), text: $username)
                            #if os(iOS)
                            .textInputAutocapitalization(.never)
                            #endif
                            .autocorrectionDisabled()
                            .textContentType(.username)
                            #if os(iOS)
                            .keyboardType(.asciiCapable)
                            #endif
                            .textFieldStyle(.roundedBorder)
                            .focused($focusedField, equals: .username)
                            .submitLabel(.next)
                            .onSubmit { focusedField = .password }

                        SecureField(settings.text(.password), text: $password)
                            .textContentType(.password)
                            #if os(iOS)
                            .keyboardType(.asciiCapable)
                            #endif
                            .textFieldStyle(.roundedBorder)
                            .focused($focusedField, equals: .password)
                            .submitLabel(.go)
                            .onSubmit(signIn)
                    }

                    if let errorMessage = model.errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline)
                            .foregroundStyle(.red)
                    }

                    Button(action: signIn) {
                        HStack {
                            if model.isSyncing { ProgressView().tint(.white) }
                            Text(model.isSyncing ? settings.text(.signingIn) : settings.text(.signIn))
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(username.isEmpty || password.isEmpty || model.isSyncing)

                    Text(settings.text(.passwordStored))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(24)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            #if os(iOS)
            .scrollDismissesKeyboard(.interactively)
            .navigationBarHidden(true)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focusedField = nil }
                }
            }
            #endif
        }
    }

    private func signIn() {
        focusedField = nil
        Task {
            await model.login(
                username: username.trimmingCharacters(in: .whitespacesAndNewlines),
                password: password
            )
        }
    }
}

private struct MainTabView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var settings: AppSettings
    @State private var showingSettings = false

    var body: some View {
        TabView {
            NavigationStack {
                DashboardView(showSettings: $showingSettings)
            }
                .tabItem { Label(settings.text(.home), systemImage: "house.fill") }
            NavigationStack {
                GradesView()
            }
                .tabItem { Label(settings.text(.grades), systemImage: "book.fill") }
            NavigationStack {
                ScheduleView()
            }
                .tabItem { Label(settings.text(.schedule), systemImage: "calendar") }
            NavigationStack {
                MessagesView()
            }
                .tabItem { Label(settings.text(.messages), systemImage: "envelope.fill") }
            NavigationStack {
                MoreView(showSettings: $showingSettings)
            }
                .tabItem { Label(settings.text(.more), systemImage: "ellipsis") }
        }
        .sheet(isPresented: $showingSettings) {
            NavigationStack {
                SettingsView()
            }
            .environmentObject(model)
            .environmentObject(settings)
        }
    }
}

extension View {
    @ViewBuilder
    func schoolListStyle() -> some View {
        #if os(macOS)
        self.listStyle(.inset)
        #else
        self.listStyle(.insetGrouped)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Color.clear.frame(height: 84)
            }
        #endif
    }
}
