import Foundation
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var isReady = false
    @Published private(set) var isAuthenticated = false
    @Published private(set) var isSyncing = false
    @Published private(set) var username = ""
    @Published private(set) var data = CachedSchoolData.empty
    @Published private(set) var notes: [SchoolNote]
    @Published private(set) var automaticSyncEnabled: Bool
    @Published var errorMessage: String?

    private let keychain = KeychainStore()
    private let store = LocalStore()
    private let notesStore = UserNotesStore()
    private var client: LibrusClient?
    private var sessionGeneration = UUID()
    private var syncingSession: UUID?
    private var automaticSyncTask: Task<Void, Never>?
    #if os(iOS)
    let watchSync = PhoneWatchSync()
    #endif

    init() {
        data = store.load()
        notes = notesStore.load()
        automaticSyncEnabled = UserDefaults.standard.object(forKey: "automaticSyncEnabled") as? Bool ?? true
        if let credentials = keychain.load() {
            username = credentials.username
            // Let the user read the last successful sync while a fresh login runs.
            isAuthenticated = data.profile != nil
            isReady = isAuthenticated
            publishToWatch()
            let generation = sessionGeneration
            Task { await restore(credentials, generation: generation) }
        } else {
            isReady = true
            publishToWatch()
        }
        startAutomaticSync()
    }

    deinit {
        automaticSyncTask?.cancel()
    }

    func login(username: String, password: String) async {
        let generation = UUID()
        sessionGeneration = generation
        errorMessage = nil
        isSyncing = true

        do {
            let newClient = LibrusClient()
            let profile = try await newClient.login(username: username, password: password)
            guard sessionGeneration == generation else { return }
            try keychain.save(username: username, password: password)
            client = newClient
            self.username = username
            isAuthenticated = true
            isReady = true
            data = .empty
            data.profile = profile
            publishToWatch()
            await sync()
        } catch {
            guard sessionGeneration == generation else { return }
            isReady = true
            errorMessage = error.localizedDescription
        }
        if sessionGeneration == generation { isSyncing = false }
    }

    func sync() async {
        guard let client else { return }
        let generation = sessionGeneration
        guard syncingSession != generation else { return }
        syncingSession = generation
        isSyncing = true
        errorMessage = nil
        var refreshed = data
        var firstError: String?
        defer {
            if syncingSession == generation {
                syncingSession = nil
                isSyncing = false
            }
        }

        do {
            refreshed.profile = try await client.fetchProfile()
        } catch {
            firstError = firstError ?? error.localizedDescription
        }
        do {
            refreshed.grades = try await client.fetchGrades()
            refreshed.gradesUpdatedAt = Date()
        } catch {
            firstError = firstError ?? error.localizedDescription
        }
        do {
            refreshed.timetable = try await client.fetchTimetable()
            refreshed.timetableUpdatedAt = Date()
        } catch {
            firstError = firstError ?? error.localizedDescription
        }
        do {
            refreshed.attendances = try await client.fetchAttendances()
        } catch {
            firstError = firstError ?? error.localizedDescription
        }
        do {
            refreshed.homeworks = try await client.fetchHomeworks()
            refreshed.homeworksUpdatedAt = Date()
        } catch {
            firstError = firstError ?? error.localizedDescription
        }
        do {
            refreshed.messages = try await client.fetchMessages()
        } catch {
            firstError = firstError ?? error.localizedDescription
        }

        // A refresh finishing after sign-out must not restore old account data.
        guard sessionGeneration == generation else { return }
        refreshed.lastSync = Date()
        data = refreshed
        errorMessage = firstError
        store.save(data)
        publishToWatch()
        isAuthenticated = true
        isReady = true
        isSyncing = false
    }

    func setAutomaticSyncEnabled(_ enabled: Bool) {
        automaticSyncEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "automaticSyncEnabled")
    }

    func note(for id: String) -> SchoolNote? {
        notes.first { $0.id == id }
    }

    func saveNote(id: String, text: String, reminds: Bool, isNoLongerRelevant: Bool) {
        let note = SchoolNote(
            id: id,
            text: text,
            reminds: reminds,
            isNoLongerRelevant: isNoLongerRelevant,
            updatedAt: Date()
        )
        notes.removeAll { $0.id == id }
        if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || reminds || isNoLongerRelevant {
            notes.append(note)
        }
        notesStore.save(notes)
    }

    func loadMessage(_ summary: MessageSummary) async -> MessageDetail? {
        guard let client else { return nil }
        do {
            return try await client.fetchMessage(id: summary.id)
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func logout() {
        sessionGeneration = UUID()
        syncingSession = nil
        isSyncing = false
        isReady = true
        keychain.delete()
        store.clear()
        notesStore.clear()
        client = nil
        username = ""
        data = .empty
        notes = []
        isAuthenticated = false
        errorMessage = nil
        publishToWatch()
    }

    private func restore(_ credentials: LibrusCredentials, generation: UUID) async {
        guard sessionGeneration == generation else { return }
        let newClient = LibrusClient()
        do {
            _ = try await newClient.login(username: credentials.username, password: credentials.password)
            guard sessionGeneration == generation else { return }
            client = newClient
            isAuthenticated = true
            isReady = true
            await sync()
        } catch {
            guard sessionGeneration == generation else { return }
            isReady = true
            if !isAuthenticated {
                errorMessage = "Please sign in again: \(error.localizedDescription)"
            } else {
                errorMessage = "Showing your last saved data. Sync failed: \(error.localizedDescription)"
            }
        }
    }

    private func publishToWatch() {
        #if os(iOS)
        watchSync.publish(data, signedIn: isAuthenticated, accountID: sessionGeneration.uuidString)
        #endif
    }

    private func startAutomaticSync() {
        automaticSyncTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: 45 * 60 * 1_000_000_000)
                } catch {
                    return
                }
                guard !Task.isCancelled, let self else { return }
                guard self.automaticSyncEnabled, self.isAuthenticated, !self.isSyncing else { continue }
                await self.sync()
            }
        }
    }
}

private final class UserNotesStore {
    private let key = "librebus.schoolNotes"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init() {
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func load() -> [SchoolNote] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let notes = try? decoder.decode([SchoolNote].self, from: data) else { return [] }
        return notes
    }

    func save(_ notes: [SchoolNote]) {
        guard let data = try? encoder.encode(notes) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
