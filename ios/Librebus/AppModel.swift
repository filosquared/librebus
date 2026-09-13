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

    init() {
        data = store.load()
        if let credentials = keychain.load() {
            username = credentials.username
            // Let the user read the last successful sync while a fresh login runs.
            isAuthenticated = data.profile != nil
            Task { await restore(credentials) }
        } else {
            isReady = true
        }
    }

    func login(username: String, password: String) async {
        errorMessage = nil
        isSyncing = true

        do {
            let newClient = LibrusClient()
            let profile = try await newClient.login(username: username, password: password)
            try keychain.save(username: username, password: password)
            client = newClient
            self.username = username
            isAuthenticated = true
            isReady = true
            data.profile = profile
            await sync()
        } catch {
            isReady = true
            errorMessage = error.localizedDescription
        }
        isSyncing = false
    }

    func sync() async {
        guard let client else { return }
        isSyncing = true
        errorMessage = nil

        do {
            data.profile = try await client.fetchProfile()
        } catch {
            handle(error)
        }
        do {
            data.grades = try await client.fetchGrades()
        } catch {
            handle(error)
        }
        do {
            data.timetable = try await client.fetchTimetable()
        } catch {
            handle(error)
        }
        do {
            data.attendances = try await client.fetchAttendances()
        } catch {
            handle(error)
        }
        do {
            data.homeworks = try await client.fetchHomeworks()
        } catch {
            handle(error)
        }
        do {
            data.messages = try await client.fetchMessages()
        } catch {
            handle(error)
        }

        data.lastSync = Date()
        store.save(data)
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
        keychain.delete()
        store.clear()
        client = nil
        username = ""
        data = .empty
        isAuthenticated = false
        errorMessage = nil
    }

    private func restore(_ credentials: LibrusCredentials) async {
        let newClient = LibrusClient()
        do {
            _ = try await newClient.login(username: credentials.username, password: credentials.password)
            client = newClient
            isAuthenticated = true
            isReady = true
            await sync()
        } catch {
            isReady = true
            if !isAuthenticated {
                errorMessage = "Please sign in again: \(error.localizedDescription)"
            } else {
                errorMessage = "Showing your last saved data. Sync failed: \(error.localizedDescription)"
            }
        }
    }

    private func handle(_ error: Error) {
        if errorMessage == nil {
            errorMessage = error.localizedDescription
        }
    }
}
