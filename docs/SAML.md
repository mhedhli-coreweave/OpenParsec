# SAML sign-in

Select **Sign in with SAML SSO**, enter the Parsec team ID or alias provided by
your administrator, and select **Continue with SAML**. Complete your company's
sign-in and MFA in the Safari sheet. On a successful session exchange, the sheet
closes and OpenParsec displays the host list. If you dismiss the browser first,
use **Continue in browser** to reopen it. **Cancel sign-in** discards the local
attempt; a new attempt can then be started. Attempts expire locally after five
minutes. Returning to the app checks the deadline before polling again.

The app does not configure the team's identity provider. Parsec must already
have SAML configured for the team. Password/2FA sign-in remains available.

## Protocol and security

- POST `https://kessel-api.parsec.app/v2/saml/login/{team}` with
  `session_scopes: ["ws.client", "api.writer"]`.
- Open the returned HTTPS `sso_url` in `SFSafariViewController`.
- POST `/v2/saml/session` with the returned `saml_request_id`, every two seconds,
  until a session is returned, a terminal error occurs, or the deadline expires.
- Treat HTTP 202 as pending, and HTTP 200/201 with a nonempty `session_id` as
  successful. Other statuses stop the attempt. The pending status still needs
  confirmation with an actual team; it has not been observed in a live login.
- Store the response in the same Keychain item as password sessions. Legacy
  hosting metadata is optional because v2 sessions may omit it.
- No IdP passwords, cookies, SAML assertions, or pasted session tokens are read
  by the app. The API session is ephemeral and does not follow redirects.
- The team alias is remembered in preferences; request IDs stay in memory.
  Sessions and request IDs must never be logged or committed.
- Cancellation invalidates timers and network requests. Attempt identifiers
  discard late responses from earlier attempts.

These native-client endpoints are used by Parsec's installed desktop client,
not a documented stable third-party SAML API. They may change independently of
OpenParsec. The browser dashboard uses a separate `/v2/saml/weblogin` flow and
should not be substituted for the native-client exchange.

References inspected on 2026-11-05:

- [Parsec SAML integration](https://support.parsec.app/hc/en-us/articles/32381486765588-Integrating-your-SAML-Identity-Provider)
- [Parsec sign-in](https://dash.parsec.app/saml/login)
- Installed Parsec desktop client 150-101a: native endpoint names, request ID and
  response field names, and session scope names.
- Unauthenticated validation: missing request fields produce HTTP 400; a
  nonexistent team and nonexistent request ID produce HTTP 404. No real account
  credentials were used in these checks.

## Validation

Run `Tests/run.sh` on macOS with Xcode installed. It checks request construction,
alias validation, HTTPS-only browser URLs, response handling, malformed/empty
session rejection, and compatibility with previously saved sessions.

Build for iPhone with Xcode 27.1:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project OpenParsec.xcodeproj -scheme OpenParsec -configuration Release \
  -sdk iphoneos -destination 'generic/platform=iOS' \
  -derivedDataPath /tmp/openparsec-saml-build \
  IPHONEOS_DEPLOYMENT_TARGET=15.0 CODE_SIGNING_ALLOWED=NO build
```

The minimum-target override is necessary for this Xcode version; upstream's
project still targets iOS 14. The resulting app is unsigned and needs the usual
provisioning and signing before installation.

Still required before calling this end-to-end verified:

1. A real team's start response and pending-session response.
2. Sign-in, MFA, session exchange, and host listing on the iPhone.
3. Cancellation, browser dismissal/reopening, timeout, and background/foreground
   transitions on the device, including identity-provider policy compatibility.
4. Relaunch/session restoration and streaming to an authorized host.

The existing installed app and its automatic renewal source IPA have not been
replaced. After device validation, replace the renewal source with this build so
future renewals retain SAML support.
