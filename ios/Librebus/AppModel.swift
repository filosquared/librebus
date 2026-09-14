import Foundation
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var isReady = false
    @Published private(set) var isAuthenticated = false
    @Published private(set) var isSyncing = false
    @Published private(set) var username = ""
    @Published private(set) var data = CachedSchoolData.empty
    @Published var errorMessage: String?

    private let keychain = KeychainStore()
    private let store = LocalStore()
    private var client: LibrusClient?
    private var sessionGeneration = UUID()
    private var syncingSession: UUID?
    #if os(iOS)
    let watchSync = PhoneWatchSync()
    #endif

    init() {
        data = store.load()
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
        client = nil
        username = ""
        data = .empty
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
}
