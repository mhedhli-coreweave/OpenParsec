import SwiftUI
import SafariServices

final class SAMLLoginModel: ObservableObject {
    struct Browser: Identifiable {
        let id = UUID()
        let url: URL
    }

    @Published private(set) var isLoading = false
    @Published var browser: Browser?
    @Published var errorMessage: String?
    @Published private(set) var waiting = false
    private var client: SAMLAuthClient?
    private var task: URLSessionDataTask?
    private var timer: Timer?
    private var timeout: Timer?
    private var generation = UUID()
    private var challenge: SAMLAuthClient.Challenge?
    private var deadline: Date?
    private var completion: ((Data) -> Void)?

    func start(team: String, completion: @escaping (Data) -> Void) {
        cancel()
        errorMessage = nil
        do {
            let request = try SAMLAuthClient.loginRequest(team: team)
            let attempt = generation
            let client = SAMLAuthClient()
            self.client = client
            self.completion = completion
            isLoading = true
            deadline = Date().addingTimeInterval(300)
            timeout = Timer.scheduledTimer(withTimeInterval: 300, repeats: false) { [weak self] _ in
                self?.fail(SAMLAuthClient.Failure.expired)
            }
            task = client.perform(request) { [weak self] result in
                guard let self = self, self.generation == attempt else { return }
                self.task = nil
                do {
                    let (data, status) = try result.get()
                    let challenge = try SAMLAuthClient.challenge(data: data, status: status)
                    self.challenge = challenge
                    self.isLoading = false
                    self.waiting = true
                    self.browser = Browser(url: challenge.sso_url)
                    self.schedulePoll()
                } catch { self.fail(error) }
            }
        } catch { fail(error) }
    }

    func resume() {
        guard waiting else { return }
        timer?.invalidate()
        poll()
    }

    func reopenBrowser() {
        guard let challenge = challenge, waiting else { return }
        browser = Browser(url: challenge.sso_url)
    }

    func cancel() {
        generation = UUID()
        task?.cancel()
        task = nil
        timer?.invalidate()
        timer = nil
        timeout?.invalidate()
        timeout = nil
        client?.invalidate()
        client = nil
        challenge = nil
        deadline = nil
        completion = nil
        browser = nil
        waiting = false
        isLoading = false
    }

    private func schedulePoll() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: false) { [weak self] _ in self?.poll() }
    }

    private func poll() {
        guard let deadline = deadline, Date() < deadline else {
            fail(SAMLAuthClient.Failure.expired)
            return
        }
        guard task == nil, let challenge = challenge, let client = client else { return }
        let attempt = generation
        do {
            task = client.perform(try SAMLAuthClient.pollRequest(id: challenge.saml_request_id)) { [weak self] result in
                guard let self = self, self.generation == attempt else { return }
                self.task = nil
                do {
                    let (data, status) = try result.get()
                    switch try SAMLAuthClient.pollResult(data: data, status: status) {
                    case .pending: self.schedulePoll()
                    case .session(let data):
                        let completion = self.completion
                        self.cancel()
                        completion?(data)
                    }
                } catch { self.fail(error) }
            }
        } catch { fail(error) }
    }

    private func fail(_ error: Error) {
        cancel()
        errorMessage = error.localizedDescription
    }

    deinit {
        timer?.invalidate()
        timeout?.invalidate()
        task?.cancel()
        client?.invalidate()
    }
}

struct SAMLBrowserView: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }
    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}
