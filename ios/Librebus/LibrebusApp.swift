import SwiftUI

@main
struct LibrebusApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
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
