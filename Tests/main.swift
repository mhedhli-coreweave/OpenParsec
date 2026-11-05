import Foundation

var checks = 0
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    checks += 1
    guard condition() else { fatalError(message) }
}
func rejects(_ message: String, _ body: () throws -> Void) {
    checks += 1
    do { try body(); fatalError(message) } catch {}
}
func data(_ object: [String: Any]) -> Data { try! JSONSerialization.data(withJSONObject: object) }

let login = try SAMLAuthClient.loginRequest(team: "  example-team_1\n")
check(login.url?.absoluteString == "https://kessel-api.parsec.app/v2/saml/login/example-team_1", "Trim team alias")
check(login.httpMethod == "POST", "Login uses POST")
let body = try JSONSerialization.jsonObject(with: login.httpBody!) as! [String: [String]]
check(body["session_scopes"] == ["ws.client", "api.writer"], "No host or team-admin scopes")
for invalid in ["", "  ", "../other", "a/b", "a?b", "a#b", "a%2Fb", "https://example.com", "m@example.com", "é", String(repeating: "a", count: 129)] {
    rejects("Reject invalid team") { _ = try SAMLAuthClient.loginRequest(team: invalid) }
}
let poll = try SAMLAuthClient.pollRequest(id: "request-fixture")
check(poll.url?.absoluteString == "https://kessel-api.parsec.app/v2/saml/session", "Fixed session endpoint")
check(poll.url?.query == nil, "Request ID does not enter URL")
let pollBody = try JSONSerialization.jsonObject(with: poll.httpBody!) as! [String: String]
check(pollBody["saml_request_id"] == "request-fixture", "Request ID in POST body")
rejects("Empty request ID rejected") { _ = try SAMLAuthClient.pollRequest(id: "") }
let challenge = try SAMLAuthClient.challenge(data: data(["sso_url": "https://idp.example.com/login", "saml_request_id": "fixture"]), status: 201)
check(challenge.sso_url.host == "idp.example.com", "HTTPS IdP URL accepted")
for url in ["http://idp.example.com", "javascript:alert(1)", "file:///tmp/a", "https://user:pass@example.com"] {
    rejects("Unsafe browser URL rejected") { _ = try SAMLAuthClient.challenge(data: data(["sso_url": url, "saml_request_id": "fixture"]), status: 201) }
}
rejects("Missing challenge ID") { _ = try SAMLAuthClient.challenge(data: data(["sso_url": "https://example.com"]), status: 200) }
rejects("Empty challenge ID") { _ = try SAMLAuthClient.challenge(data: data(["sso_url": "https://example.com", "saml_request_id": ""]), status: 200) }
if case .pending = try SAMLAuthClient.pollResult(data: Data(), status: 202) { check(true, "Pending") }
else { fatalError("Accepted should be pending") }
for status in [200, 201] {
    let fixture = data(["session_id": "fixture-not-a-real-token", "user_id": 7])
    if case .session(let saved) = try SAMLAuthClient.pollResult(data: fixture, status: status) {
        check(saved == fixture, "Preserve session response for Keychain")
    } else { fatalError("Missing session") }
}
let legacy = data(["session_id": "fixture", "user_id": 7, "instance_id": "old", "host_peer_id": "host"])
check(try! JSONDecoder().decode(ClientInfo.self, from: legacy).instance_id == "old", "Legacy session compatibility")
for fixture in [data([:]), data(["session_id": ""]), data(["session_id": " \n"]), data(["session_id": 123]), Data("not-json".utf8)] {
    rejects("Malformed sessions cannot authenticate") { _ = try SAMLAuthClient.pollResult(data: fixture, status: 200) }
}
for status in [301, 400, 401, 403, 404, 410, 429, 500] {
    rejects("Non-success status cannot authenticate") { _ = try SAMLAuthClient.pollResult(data: legacy, status: status) }
}
print("Passed \(checks) SAML protocol checks")
