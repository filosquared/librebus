// Offline regression checks. Compile with LibrusClient.swift and Models.swift.
import Foundation

final class AuthFixtureProtocol: URLProtocol {
    static var requests: [URLRequest] = []
    static let lock = NSLock()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock()
        Self.requests.append(request)
        Self.lock.unlock()
        let url = request.url!
        var responseURL = url
        var body = "{}"
        switch url.path {
        case "/loguj/portalRodzina":
            responseURL = URL(string: "https://api.librus.pl/OAuth/Authorization?client_id=46")!
        case "/OAuth/Authorization":
            precondition(request.httpMethod == "POST")
            body = #"{"status":"ok","goTo":"/OAuth/Authorization/2FA?client_id=46"}"#
        case "/OAuth/Authorization/2FA":
            precondition(url.host == "api.librus.pl")
            responseURL = URL(string: "https://synergia.librus.pl/uczen/index")!
        case "/gateway/api/2.0/Auth/TokenInfo":
            body = #"{"UserIdentifier":"fixture-user"}"#
        case "/gateway/api/2.0/Me":
            body = #"{"Me":{"Account":{"FirstName":"Fixture","LastName":"Student"}}}"#
        case "/gateway/api/2.0/Auth/UserInfo/fixture-user", "/gateway/api/2.0/UserProfile", "/gateway/api/2.0/Users", "/gateway/api/2.0/Classes":
            break
        default:
            preconditionFailure("Unexpected request in offline login sequence")
        }
        let response = HTTPURLResponse(url: responseURL, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@main struct AuthChecks {
    static func rejects(_ error: LibrusClientError, _ action: () throws -> Void) {
        do { try action(); preconditionFailure("Expected rejection") }
        catch let actual as LibrusClientError { precondition(actual == error) }
        catch { preconditionFailure("Unexpected error") }
    }

    static func main() async throws {
        let response = HTTPURLResponse(url: URL(string: "https://api.librus.pl/OAuth/Authorization")!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        let next = try LibrusClient.loginContinuation(data: Data(#"{"status":"ok","goTo":"/OAuth/Authorization/2FA?client_id=46"}"#.utf8), response: response)
        precondition(next.host == "api.librus.pl" && next.path == "/OAuth/Authorization/2FA")
        rejects(.invalidCredentials) {
            _ = try LibrusClient.loginContinuation(data: Data(#"{"status":"error"}"#.utf8), response: response)
        }
        for payload in ["<html>Login</html>", "{}", #"{"status":"ok"}"#] {
            rejects(.loginFlowUnavailable) {
                _ = try LibrusClient.loginContinuation(data: Data(payload.utf8), response: response)
            }
        }
        for url in ["", "https://portal.librus.pl/rodzina", "https://synergia.librus.pl/OAuth/Authorization", "http://api.librus.pl/OAuth/Authorization", "https://api.librus.pl:444/OAuth/Authorization", "https://api.librus.pl.evil.example/OAuth/Authorization", "https://user:pass@api.librus.pl/OAuth/Authorization", "https://api.librus.pl/OAuth/Authorization?error=invalid_request"] {
            rejects(.loginFlowUnavailable) { _ = try LibrusClient.authorizationURL(url) }
        }
        let encoded = String(data: LibrusClient.formBody(["pass": "a+b &%=ż"]), encoding: .utf8)!
        precondition(encoded == "pass=a%2Bb%20%26%25%3D%C5%BC")

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [AuthFixtureProtocol.self]
        let client = LibrusClient(configuration: config)
        do {
            _ = try await client.login(username: "fixture@example.invalid", password: "fake")
            preconditionFailure("Email must not be sent to Synergia")
        } catch let error as LibrusClientError {
            precondition(error == .synergiaAccountRequired)
        }
        precondition(AuthFixtureProtocol.requests.isEmpty)
        let profile = try await client.login(username: "1234567u", password: "fake+password")
        precondition(profile.firstName == "Fixture")
        precondition(AuthFixtureProtocol.requests.count == 9)
        precondition(AuthFixtureProtocol.requests.filter { $0.httpMethod == "POST" }.count == 1)
        precondition(AuthFixtureProtocol.requests.allSatisfy { $0.value(forHTTPHeaderField: "Cookie") == nil })
        print("iOS authentication checks passed (offline; no real credentials).")
    }
}
