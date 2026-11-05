import Foundation

/// Parsec's native-client SAML exchange. No IdP credentials or browser cookies
/// pass through the app. Keep request IDs and session tokens out of logs.
final class SAMLAuthClient: NSObject, URLSessionTaskDelegate {
    struct Challenge: Decodable {
        let sso_url: URL
        let saml_request_id: String
    }

    enum PollResult {
        case pending
        case session(Data)
    }

    enum Failure: LocalizedError {
        case invalidTeam, invalidResponse, server(Int), expired, insecureURL

        var errorDescription: String? {
            switch self {
            case .invalidTeam: return "Enter your Parsec team ID or SAML alias."
            case .invalidResponse: return "Parsec returned an unexpected sign-in response. Please try again."
            case .server(404): return "The team or sign-in request was not found. Check your team ID or alias and try again."
            case .server(429): return "Too many sign-in attempts. Please wait before trying again."
            case .server(let status): return "Parsec could not complete sign-in (HTTP \(status)). Please try again."
            case .expired: return "SAML sign-in expired. Please start again."
            case .insecureURL: return "Parsec returned an unsafe sign-in URL. Sign-in was stopped."
            }
        }
    }

    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 30
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        return URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }()

    static func loginRequest(team: String) throws -> URLRequest {
        let team = team.trimmingCharacters(in: .whitespacesAndNewlines)
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_")
        guard !team.isEmpty, team.utf8.count <= 128,
              team.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
            throw Failure.invalidTeam
        }
        return try request(path: "/v2/saml/login/\(team)", body: [
            "session_scopes": ["ws.client", "api.writer"]
        ])
    }

    static func pollRequest(id: String) throws -> URLRequest {
        guard !id.isEmpty else { throw Failure.invalidResponse }
        return try request(path: "/v2/saml/session", body: ["saml_request_id": id])
    }

    private static func request(path: String, body: [String: Any]) throws -> URLRequest {
        var request = URLRequest(url: URL(string: "https://kessel-api.parsec.app\(path)")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("OpenParsec/1.4 iOS", forHTTPHeaderField: "User-Agent")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    static func challenge(data: Data, status: Int) throws -> Challenge {
        guard (200...299).contains(status) else { throw Failure.server(status) }
        guard let challenge = try? JSONDecoder().decode(Challenge.self, from: data),
              !challenge.saml_request_id.isEmpty else { throw Failure.invalidResponse }
        guard challenge.sso_url.scheme?.lowercased() == "https",
              let host = challenge.sso_url.host, !host.isEmpty,
              challenge.sso_url.user == nil, challenge.sso_url.password == nil else {
            throw Failure.insecureURL
        }
        return challenge
    }

    static func pollResult(data: Data, status: Int) throws -> PollResult {
        // Accepted means the browser exchange is unfinished. Never treat a
        // rejected or missing request as successful, or retry it indefinitely.
        if status == 202 { return .pending }
        guard status == 200 || status == 201 else { throw Failure.server(status) }
        guard let info = try? JSONDecoder().decode(ClientInfo.self, from: data),
              !info.session_id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw Failure.invalidResponse
        }
        return .session(data)
    }

    @discardableResult
    func perform(_ request: URLRequest, completion: @escaping (Result<(Data, Int), Error>) -> Void) -> URLSessionDataTask {
        let task = session.dataTask(with: request) { data, response, error in
            let result: Result<(Data, Int), Error>
            if let error = error { result = .failure(error) }
            else if let data = data, let response = response as? HTTPURLResponse {
                result = .success((data, response.statusCode))
            } else { result = .failure(Failure.invalidResponse) }
            DispatchQueue.main.async { completion(result) }
        }
        task.resume()
        return task
    }

    func invalidate() { session.invalidateAndCancel() }

    // Never forward a SAML request ID to a redirected endpoint.
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
