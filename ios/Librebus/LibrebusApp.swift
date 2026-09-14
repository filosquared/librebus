import SwiftUI

@main
struct LibrebusApp: App {
    @StateObject private var model = AppModel()
    @StateObject private var settings = AppSettings()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .environmentObject(settings)
                #if os(macOS)
                .frame(minWidth: 520, idealWidth: 680, maxWidth: .infinity, minHeight: 620, idealHeight: 820, maxHeight: .infinity)
                #endif
        }
        #if os(macOS)
        .defaultSize(width: 680, height: 820)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Sync school data") { Task { await model.sync() } }
                    .keyboardShortcut("r", modifiers: .command)
                    .disabled(!model.isAuthenticated || model.isSyncing)
            }
        }
        #endif
    }
}
