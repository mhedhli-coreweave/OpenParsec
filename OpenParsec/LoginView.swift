import SwiftUI
import os

struct LoginView: View {
	var controller: ContentView?

	@StateObject private var saml = SAMLLoginModel()
	@State private var useSAML = false
	@AppStorage("samlTeamAlias") private var teamAlias = ""

	@State var inputEmail: String = ""
	@State var inputPassword: String = ""
	@State var inputTFA: String = ""
	@State var isTFAOn: Bool = false
	@State private var presentTFAAlert = false
	@State var isLoading: Bool = false
	@State var showAlert: Bool = false
	@State var alertText: String = ""

	init(_ controller: ContentView?) {
		self.controller = controller
	}

	var body: some View {
		ZStack {
			// Background
			Rectangle()
				.fill(Color("BackgroundGray"))
				.edgesIgnoringSafeArea(.all)

			// Login controls
			VStack(spacing: 8) {
				HStack(spacing: 2) {
					Image("IconTransparent")
						.resizable()
						.aspectRatio(contentMode: .fit)
					Image("LogoShadow")
						.resizable()
						.aspectRatio(contentMode: .fit)
						.padding([.top, .bottom, .trailing])
				}
				.frame(height: 80)
				if useSAML {
					samlControls
				} else {
					TextField("Email", text: $inputEmail)
						.padding()
						.background(Rectangle().fill(Color("BackgroundField")))
						.cornerRadius(8)
						.disableAutocorrection(true)
						.autocapitalization(/*@START_MENU_TOKEN@*/.none/*@END_MENU_TOKEN@*/)
						.keyboardType(.emailAddress)
						.textContentType(.emailAddress)
					SecureField("Password", text: $inputPassword, onCommit: { authenticate() })
						.padding()
						.background(Rectangle().fill(Color("BackgroundField")))
						.cornerRadius(8)
						.disableAutocorrection(true)
						.autocapitalization(/*@START_MENU_TOKEN@*/.none/*@END_MENU_TOKEN@*/)
						.textContentType(.password)
					Button(action: {authenticate()}) {
						ZStack {
							Rectangle()
								.fill(Color("AccentColor"))
								.cornerRadius(8)
							Text("Login")
								.foregroundColor(.white)
						}
						.frame(height: 54)
					}
                }
                Button(useSAML ? "Use email and password" : "Sign in with SAML SSO") {
                    saml.cancel()
                    useSAML.toggle()
                }
                .padding(.top, 12)
            }

            .padding()
			.frame(maxWidth: 400)
			.disabled(isLoading) // Disable when loading

			// Loading elements
			if isLoading || presentTFAAlert {
				ZStack {
					Rectangle() // Darken background
						.fill(Color.black)
						.opacity(0.5)
						.edgesIgnoringSafeArea(.all)
					VStack {
						if isLoading {
							ActivityIndicator(isAnimating: $isLoading, style: .large, tint: .white)
							 .padding()
						 Text("Loading...")
							 .multilineTextAlignment(.center)
						} else if presentTFAAlert {
							Text("Please enter your 2FA code from your authenticator app")
								.multilineTextAlignment(.center)
							SecureField("2FA Code", text: $inputTFA)
								.padding()
								.background(Rectangle().fill(Color("BackgroundField")))
								.foregroundColor(Color("Foreground"))
								.cornerRadius(8)
								.disableAutocorrection(true)
								.autocapitalization(/*@START_MENU_TOKEN@*/.none/*@END_MENU_TOKEN@*/)
								.textContentType(.oneTimeCode)
							HStack {
								Button(action: {presentTFAAlert = false}) {
									ZStack {
										Rectangle()
											.fill(Color("BackgroundButton"))
											.cornerRadius(8)
										Text("Cancel")
											.foregroundColor(Color("Foreground"))
									}
									.frame(height: 54)
								}
								Button(action: {authenticate(inputTFA)}) {
									ZStack {
										Rectangle()
											.fill(Color("AccentColor"))
											.cornerRadius(8)
										Text("Enter")
											.foregroundColor(.white)
									}
									.frame(height: 54)
								}
							}
						}
					}
					.padding()
					.background(Rectangle().fill(Color("BackgroundPrompt")))
					.cornerRadius(8)
					.padding()
				}
			}
		}
		.foregroundColor(Color("Foreground"))
		.alert(isPresented: $showAlert) {
			Alert(title: Text("Login Failed"), message: Text(alertText))
		}
		.sheet(item: $saml.browser, onDismiss: { saml.resume() }) { browser in
            SAMLBrowserView(url: browser.url).edgesIgnoringSafeArea(.all)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            saml.resume()
            retryRestore()
        }
        .onDisappear { saml.cancel() }
		.onReceive(NotificationCenter.default.publisher(for: UIApplication.protectedDataDidBecomeAvailableNotification)) { _ in retryRestore() }
	}

    private var samlControls: some View {
        VStack(spacing: 12) {
            TextField("Team ID or SAML alias", text: $teamAlias)
                .padding()
                .background(Color("BackgroundField"))
                .cornerRadius(8)
                .disableAutocorrection(true)
                .autocapitalization(.none)
                .disabled(saml.isLoading || saml.waiting)
                .accessibilityIdentifier("samlTeamAlias")
            Text("Use the team ID or alias supplied by your Parsec administrator.")
                .font(.footnote)
            if saml.waiting {
                Text("Complete sign-in in the browser, then return here. This request expires after five minutes.")
                Button("Continue in browser") { saml.reopenBrowser() }
            } else {
                Button(saml.isLoading ? "Starting sign-in…" : "Continue with SAML") {
                    saml.start(team: teamAlias) { data in completeLogin(data) }
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color("AccentColor"))
                .foregroundColor(.white)
                .cornerRadius(8)
                .disabled(saml.isLoading || teamAlias.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("samlSignIn")
            }
            if saml.isLoading || saml.waiting {
                Button("Cancel sign-in") { saml.cancel() }
            }
            if let message = saml.errorMessage {
                Text(message).foregroundColor(.red).font(.footnote)
            }
        }
    }

    private func completeLogin(_ data: Data) {
        guard let info = try? JSONDecoder().decode(ClientInfo.self, from: data), !info.session_id.isEmpty else {
            alertText = "Bad response from the server"
            showAlert = true
            return
        }
        guard saveToKeychain(data: data, key: GLBDataModel.shared.SessionKeyChainKey) else { return }
        NetworkHandler.clinfo = info
        controller?.setView(.main)
    }

	func retryRestore() {
		if !isLoading && !presentTFAAlert && !saml.isLoading && !saml.waiting, let c = controller {
			c.retryRestore()
		}
	}

	@discardableResult
    func saveToKeychain(data: Data, key: String) -> Bool {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrAccount as String: key]
        let attributes: [String: Any] = [kSecValueData as String: data, kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock]
        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(query.merging(attributes) { _, value in value } as CFDictionary, nil)
        }
        guard status == errSecSuccess else {
            alertText = "Could not securely save your session. Unlock the device and try again."
            showAlert = true
            return false
        }
        return true
    }

	func authenticate(_ tfa: String? = "") {
		#if DEBUG
		if inputEmail == "test@example.com" { // skip authentication (DEBUG ONLY)
			if let c = controller {
				c.setView(.main)
			}
			return
		}
		#endif

		withAnimation { isLoading = true }

		let apiURL = URL(string: "https://kessel-api.parsec.app/v1/auth")!

		var request = URLRequest(url: apiURL)
		request.httpMethod = "POST"
		request.setValue("application/json", forHTTPHeaderField: "Content-Type")
		request.setValue("parsec/150-93b Windows/11 libmatoya/4.0", forHTTPHeaderField: "User-Agent")
		request.httpBody = try? JSONSerialization.data(withJSONObject:
		[
			"email": inputEmail,
			"password": inputPassword,
			"tfa": tfa
		], options: [])

		let task = URLSession.shared.dataTask(with: request) { (data, response, error) in
			DispatchQueue.main.async {
				isLoading = false
				if let data = data {
					guard let statusCode = (response as? HTTPURLResponse)?.statusCode else {
						alertText = "Bad response from the server"
						showAlert = true
						return
					}
					let decoder = JSONDecoder()

					if statusCode == 201 { // 201 Created
						presentTFAAlert = false
						completeLogin(data)
					} else if statusCode >= 400 { // 4XX client errors
						guard let info: ErrorInfo = try? decoder.decode(ErrorInfo.self, from: data) else {
							alertText = "Login failed (HTTP \(statusCode))"
							showAlert = true
							return
						}

						let json = try? JSONSerialization.jsonObject(with: data, options: [])
						if let dict = json as? [String: Any], let isTFARequired = dict["tfa_required"] as? Bool {
							print("Code output:")
							print(dict)
							if isTFARequired {
								presentTFAAlert = true
							} else {
								alertText = "Error: \(info)"
								showAlert = true
							}
						} else {
							alertText = info.error
							showAlert = true
						}
					} else {
						alertText = "Login failed (HTTP \(statusCode))"
						showAlert = true
					}
				} else {
					alertText = error?.localizedDescription ?? "Could not reach the server"
					showAlert = true
				}
			}
		}
		task.resume()
	}
}

struct LoginView_Previews: PreviewProvider {
	static var previews: some View {
		LoginView(nil)
	}
}
