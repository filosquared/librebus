import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

struct GitHubRelease: Codable, Equatable, Identifiable {
    let tagName: String
    let name: String?
    let body: String?
    let htmlURL: URL
    let prerelease: Bool
    let draft: Bool

    var id: String { tagName }

    var displayName: String {
        let trimmedName = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmedName.isEmpty ? tagName : trimmedName
    }

    private enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case body
        case htmlURL = "html_url"
        case prerelease
        case draft
    }
}

enum ReleaseVersion {
    static func isNewer(_ latest: String, than current: String) -> Bool {
        let latestComponents = components(from: latest)
        let currentComponents = components(from: current)
        guard !latestComponents.isEmpty, !currentComponents.isEmpty else { return false }

        let count = max(latestComponents.count, currentComponents.count)
        for index in 0..<count {
            let latestValue = index < latestComponents.count ? latestComponents[index] : 0
            let currentValue = index < currentComponents.count ? currentComponents[index] : 0
            if latestValue != currentValue { return latestValue > currentValue }
        }
        return false
    }

    private static func components(from raw: String) -> [Int] {
        raw.split { !$0.isNumber }.compactMap { Int($0) }
    }
}

enum GitHubReleaseClientError: Error {
    case invalidResponse
    case invalidReleaseURL
}

protocol GitHubReleaseProviding {
    func fetchLatest() async throws -> GitHubRelease
}

final class GitHubReleaseClient {
    static let latestReleaseURL = URL(string: "https://api.github.com/repos/filosquared/librecap/releases/latest")!

    private let session: URLSession
    private let endpoint: URL

    init(session: URLSession = .shared, endpoint: URL = GitHubReleaseClient.latestReleaseURL) {
        self.session = session
        self.endpoint = endpoint
    }

    func fetchLatest() async throws -> GitHubRelease {
        var request = URLRequest(url: endpoint)
        request.timeoutInterval = 10
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("LibreCap Update Checker", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw GitHubReleaseClientError.invalidResponse
        }

        let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
        guard release.htmlURL.scheme?.lowercased() == "https",
              release.htmlURL.host?.lowercased() == "github.com" else {
            throw GitHubReleaseClientError.invalidReleaseURL
        }
        return release
    }
}

extension GitHubReleaseClient: GitHubReleaseProviding {}
