import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var settings: AppSettings
    @State private var draftAppName = ""

    var body: some View {
        Form {
            Section(settings.text(.appName)) {
                TextField(settings.text(.appName), text: $draftAppName)
                    .onSubmit(saveName)
                HStack {
                    Button(settings.text(.save), action: saveName)
                    Button(settings.text(.reset), action: resetName)
                        .buttonStyle(.borderless)
                }
            }

            Section(settings.text(.language)) {
                Picker(settings.text(.language), selection: $settings.language) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.title).tag(language)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section(settings.text(.automaticSync)) {
                Toggle(settings.text(.automaticSync), isOn: Binding(
                    get: { model.automaticSyncEnabled },
                    set: model.setAutomaticSyncEnabled
                ))
                Text(settings.text(.automaticSyncDescription))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Label(settings.text(.every45Minutes), systemImage: "clock")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Section(settings.text(.account)) {
                Button(role: .destructive, action: model.logout) {
                    Label(settings.text(.signOut), systemImage: "rectangle.portrait.and.arrow.right")
                }
            }
        }
        .navigationTitle(settings.text(.settings))
        .onAppear { draftAppName = settings.appName }
    }

    private func saveName() {
        let name = draftAppName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        settings.appName = name
    }

    private func resetName() {
        draftAppName = "Librebus"
        saveName()
    }
}
