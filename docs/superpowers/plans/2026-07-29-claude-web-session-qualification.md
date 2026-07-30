# Claude Web Session Qualification Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> superpowers:subagent-driven-development (recommended) or
> superpowers:executing-plans to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prove that two isolated Claude.ai web sessions can authenticate
different accounts and independently retrieve five-hour and weekly
subscription usage without exposing their cookies.

**Architecture:** A new `UsageMeterClaudeWeb` module owns identified WebKit
profiles, embedded login, cookie retrieval, and browser-shaped Claude web API
requests. The login coordinator uses a real popup `WKWebView`, cookie
observation plus bounded polling, and a reload fallback adapted from the
MIT-licensed Claude Usage Tracker behavior. Provider responses are decoded by
the existing normalized usage model, and an interactive probe supplies the
real two-account qualification gate.

**Tech Stack:** Swift 6.2, macOS 26, Swift Package Manager, AppKit, WebKit,
Foundation, Swift Testing

## Global Constraints

- Keep every Claude account in a separate persistent
  `WKWebsiteDataStore(forIdentifier:)`.
- Never print, log, cache, fixture, or copy a `sessionKey`, `cf_clearance`, or
  `__cf_bm` value outside its WebKit data store.
- Fetch cookies only when starting a provider request; the existing
  `AccountRefresher` remains the sole ten-minute usage-request gate.
- Send traffic directly from the Mac to `https://claude.ai`.
- Preserve the last good normalized snapshot on transient failure.
- Do not add a third-party package. Reimplement the small required behaviors
  using native WebKit and Foundation.
- Do not remove the existing OAuth probe until the web-session gate passes.
- Stop after the first real-account failure and record the sanitized outcome
  before changing the design.

---

### Task 1: Reusable Claude Usage Decoder

**Files:**
- Create:
  `Sources/UsageMeterCore/Providers/ClaudeUsageDecoder.swift`
- Modify:
  `Sources/UsageMeterCore/Providers/ClaudeUsageClient.swift`
- Create:
  `Tests/UsageMeterCoreTests/ClaudeUsageDecoderTests.swift`

**Interfaces:**
- Consumes: Claude usage JSON containing `five_hour` and `seven_day`.
- Produces:
  `ClaudeUsageDecoder.decode(_:accountID:fetchedAt:) throws -> UsageSnapshot`.

- [ ] **Step 1: Write the failing decoder test**

```swift
import Foundation
import Testing
@testable import UsageMeterCore

@Suite
struct ClaudeUsageDecoderTests {
    @Test
    func decodesRequiredWindows() throws {
        let data = try #require(
            try? Data(
                contentsOf: Bundle.module.url(
                    forResource: "claude-usage",
                    withExtension: "json"
                )!
            )
        )
        let accountID = UUID()
        let fetchedAt = Date(timeIntervalSince1970: 1_700_000_000)

        let snapshot = try ClaudeUsageDecoder().decode(
            data,
            accountID: accountID,
            fetchedAt: fetchedAt
        )

        #expect(snapshot.accountID == accountID)
        #expect(snapshot.fetchedAt == fetchedAt)
        #expect(snapshot.windows.map(\.kind) == [.short, .weekly])
        #expect(snapshot.windows.map(\.duration) == [18_000, 604_800])
    }
}
```

- [ ] **Step 2: Run the test and verify RED**

Run:

```bash
swift test --filter ClaudeUsageDecoderTests
```

Expected: compilation fails because `ClaudeUsageDecoder` does not exist.

- [ ] **Step 3: Extract the strict decoder**

Create a public, stateless `ClaudeUsageDecoder` and move the response payload,
date decoding, range validation, duration mapping, and
`unsupportedResponse` mapping out of `ClaudeUsageClient`. Inject that decoder
into `ClaudeUsageClient` and preserve every existing request behavior.

```swift
public struct ClaudeUsageDecoder: Sendable {
    public init() {}

    public func decode(
        _ data: Data,
        accountID: UUID,
        fetchedAt: Date
    ) throws -> UsageSnapshot
}
```

- [ ] **Step 4: Run focused and full tests**

Run:

```bash
swift test --filter ClaudeUsageDecoderTests
swift test
```

Expected: the new decoder test and all existing tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/UsageMeterCore/Providers/ClaudeUsageDecoder.swift \
  Sources/UsageMeterCore/Providers/ClaudeUsageClient.swift \
  Tests/UsageMeterCoreTests/ClaudeUsageDecoderTests.swift
git commit -m "Extract Claude usage response decoder"
```

---

### Task 2: Isolated WebKit Profile and Browser-Shaped Usage Client

**Files:**
- Modify: `Package.swift`
- Create:
  `Sources/UsageMeterClaudeWeb/ClaudeWebProfile.swift`
- Create:
  `Sources/UsageMeterClaudeWeb/ClaudeWebCookieSource.swift`
- Create:
  `Sources/UsageMeterClaudeWeb/ClaudeWebUsageClient.swift`
- Create:
  `Tests/UsageMeterClaudeWebTests/ClaudeWebUsageClientTests.swift`
- Copy:
  `Tests/UsageMeterClaudeWebTests/Fixtures/claude-usage.json`
- Create:
  `Tests/UsageMeterClaudeWebTests/Fixtures/claude-organizations.json`

**Interfaces:**
- Consumes: `HTTPTransport`, `ClaudeUsageDecoder`, a WebKit profile UUID, and
  an organization UUID.
- Produces:
  `ClaudeWebUsageClient.organizations(profileID:)` and
  `ClaudeWebUsageClient.fetchUsage(accountID:profileID:organizationID:now:)`.

- [ ] **Step 1: Add the module and write failing request tests**

Add `UsageMeterClaudeWeb` as a library target depending on `UsageMeterCore`,
and `UsageMeterClaudeWebTests` as a test target with its fixture directory
copied as resources.

The tests use a fake cookie source containing distinct marker cookies for two
profile IDs and the existing recording HTTP transport. Assert these real
request contracts:

```swift
let organizations = try await client.organizations(profileID: firstProfile)
#expect(organizations == [
    ClaudeOrganization(
        id: UUID(uuidString: "10000000-0000-0000-0000-000000000001")!,
        name: "Personal",
        capabilities: ["chat", "claude_max"]
    )
])

let request = try #require(await transport.lastRequest)
#expect(request.url?.absoluteString == "https://claude.ai/api/organizations")
#expect(request.value(forHTTPHeaderField: "Cookie") == [
    "sessionKey=first-session",
    "cf_clearance=first-clearance",
    "__cf_bm=first-bm"
].joined(separator: "; "))
#expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
#expect(request.value(forHTTPHeaderField: "Origin") == "https://claude.ai")
#expect(request.value(forHTTPHeaderField: "Referer") == "https://claude.ai")
```

Add a second test that fetches
`https://claude.ai/api/organizations/{organizationID}/usage`, decodes the
fixture into short and weekly windows, and proves the second profile's cookies
are used instead of the first profile's cookies.

Add focused tests proving:

- No `sessionKey` means `reauthenticationRequired` without network traffic.
- HTTP 401 or 403 means `reauthenticationRequired`.
- HTTP 429 preserves `Retry-After`.
- Organization JSON must contain valid UUID, name, and capabilities.

- [ ] **Step 2: Run the tests and verify RED**

Run:

```bash
swift test --filter ClaudeWebUsageClientTests
```

Expected: compilation fails because the new module and types do not exist.

- [ ] **Step 3: Implement the minimal WebKit cookie boundary**

```swift
public struct ClaudeWebProfile: Codable, Equatable, Sendable {
    public let id: UUID

    public init(id: UUID) {
        self.id = id
    }
}

@MainActor
public protocol ClaudeWebCookieSource: AnyObject {
    func cookies(for url: URL, profileID: UUID) async -> [HTTPCookie]
}

@MainActor
public final class WebKitClaudeCookieSource: ClaudeWebCookieSource {
    public init() {}

    public func cookies(for url: URL, profileID: UUID) async -> [HTTPCookie] {
        let store = WKWebsiteDataStore(forIdentifier: profileID)
        return await store.httpCookieStore.cookies(for: url)
    }
}
```

The implementation filters cookies to `sessionKey`, `cf_clearance`, and
`__cf_bm`, orders them exactly in that order, and creates one `Cookie` header.
The session value exists only in the request object in memory.

`ClaudeWebUsageClient` uses a Safari-shaped user agent plus `Accept`,
`Origin`, and `Referer`. It never logs requests or response bodies. It uses
`ClaudeUsageDecoder` for successful usage responses and performs strict status
mapping consistent with the existing provider client.

- [ ] **Step 4: Run focused and full tests**

Run:

```bash
swift test --filter ClaudeWebUsageClientTests
swift test
```

Expected: all tests pass with no warnings.

- [ ] **Step 5: Commit**

```bash
git add Package.swift Sources/UsageMeterClaudeWeb \
  Tests/UsageMeterClaudeWebTests
git commit -m "Add isolated Claude web usage client"
```

---

### Task 3: Embedded Login with macOS 26 Cookie and SSO Handling

**Files:**
- Create:
  `Sources/UsageMeterClaudeWeb/ClaudeLoginCookieDetector.swift`
- Create:
  `Sources/UsageMeterClaudeWeb/ClaudeLoginSession.swift`
- Create:
  `Tests/UsageMeterClaudeWebTests/ClaudeLoginCookieDetectorTests.swift`
- Create:
  `Tests/UsageMeterClaudeWebTests/ClaudeWebProfileStoreTests.swift`

**Interfaces:**
- Consumes: a provisional WebKit profile UUID and the Claude login URL.
- Produces: `ClaudeLoginSession.webView`, a successful profile UUID callback,
  cancellation cleanup, and profile deletion.

- [ ] **Step 1: Write failing cookie and profile-isolation tests**

Test the pure detector rather than WebKit callbacks:

```swift
@Test
func recognizesOnlyClaudeSessionCookies() {
    let cookies = [
        makeCookie(name: "unrelated", value: "x", domain: ".claude.ai"),
        makeCookie(name: "sessionKey", value: "secret", domain: ".claude.ai")
    ]

    #expect(ClaudeLoginCookieDetector.hasSession(in: cookies))
}

@Test
func rejectsSessionCookieFromAnotherDomain() {
    let cookies = [
        makeCookie(name: "sessionKey", value: "secret", domain: ".example.com")
    ]

    #expect(!ClaudeLoginCookieDetector.hasSession(in: cookies))
}
```

Add a main-actor test that creates two identified stores and verifies both
report their requested, distinct identifiers. Release them, remove both stores,
and fail the test if cleanup throws.

- [ ] **Step 2: Run the tests and verify RED**

Run:

```bash
swift test --filter ClaudeLoginCookieDetectorTests
swift test --filter ClaudeWebProfileStoreTests
```

Expected: compilation fails because the detector and profile store do not
exist.

- [ ] **Step 3: Implement the embedded login coordinator**

`ClaudeLoginSession` must:

- Create its main web view with
  `WKWebsiteDataStore(forIdentifier: profileID)`.
- Load `https://claude.ai/login`.
- Set `javaScriptCanOpenWindowsAutomatically`.
- Implement `WKUIDelegate` by creating a real popup `WKWebView` from WebKit's
  supplied configuration, placing it in an `NSPanel`, and returning it so
  Google SSO retains `window.opener` and the same cookie store.
- Observe `WKHTTPCookieStore` changes.
- Poll the cookie store once per second because macOS 26 may not notify for
  network-process `Set-Cookie` changes and Claude is a single-page app.
- If the main view has left `/login` but the cookie remains invisible for
  three polls, call `reloadFromOrigin()`. Limit this to three reloads.
- Stop the timer immediately after detecting a Claude-domain `sessionKey`.
- Never expose the cookie value through the completion callback.
- On cancellation, stop observers and timers, close popup and main windows,
  release all web views, and remove the provisional data store.

Profile removal uses:

```swift
try await WKWebsiteDataStore.remove(forIdentifier: profileID)
```

only after every `WKWebView` using that identifier is released.

- [ ] **Step 4: Run focused and full tests**

Run:

```bash
swift test --filter ClaudeLoginCookieDetectorTests
swift test --filter ClaudeWebProfileStoreTests
swift test
```

Expected: all tests pass and both test data stores are removed.

- [ ] **Step 5: Commit**

```bash
git add Sources/UsageMeterClaudeWeb/ClaudeLoginCookieDetector.swift \
  Sources/UsageMeterClaudeWeb/ClaudeLoginSession.swift \
  Tests/UsageMeterClaudeWebTests/ClaudeLoginCookieDetectorTests.swift \
  Tests/UsageMeterClaudeWebTests/ClaudeWebProfileStoreTests.swift
git commit -m "Add isolated Claude web login session"
```

---

### Task 4: Interactive Two-Account Qualification Probe

**Files:**
- Modify: `Package.swift`
- Create: `Sources/ClaudeWebProbe/ClaudeWebProbe.swift`
- Create: `Sources/ClaudeWebProbe/ClaudeWebProbeView.swift`
- Create: `Sources/ClaudeWebProbe/ClaudeWebProbeModel.swift`
- Modify: `docs/provider-qualification.md`

**Interfaces:**
- Consumes: `UsageMeterClaudeWeb`, a caller-supplied profile UUID, and
  interactive login.
- Produces: sanitized normalized usage on stdout and a dated two-profile
  qualification record.

- [ ] **Step 1: Add the executable target and minimal command contract**

Add a `ClaudeWebProbe` executable depending on `UsageMeterCore` and
`UsageMeterClaudeWeb`.

Commands:

```text
ClaudeWebProbe login <profile-uuid>
ClaudeWebProbe delete <profile-uuid>
```

`login` opens a 520-by-680 login window. When a session cookie appears, it
loads organizations through `ClaudeWebUsageClient`, shows organization names
only inside the window, and lets the user qualify one organization. Successful
qualification prints only:

- The local profile UUID
- Organization count
- Window kinds
- Durations
- Consumed fractions
- Reset timestamps

It never prints organization UUIDs, names, email addresses, cookies, headers,
or raw responses. `delete` releases any process-owned web views and removes the
identified data store.

- [ ] **Step 2: Build the probe**

Run:

```bash
swift build --product ClaudeWebProbe
```

Expected: the probe builds without errors or warnings.

- [ ] **Step 3: Qualify the first profile**

Generate a local UUID and run the probe:

```bash
claude_profile_a=$(uuidgen | tr '[:upper:]' '[:lower:]')
swift run ClaudeWebProbe login "$claude_profile_a"
```

Jesse signs in to the first Claude account and confirms the organization shown
in the window. Expected sanitized output contains one 18,000-second window and
one 604,800-second window.

- [ ] **Step 4: Qualify a second profile and prove persistence**

```bash
claude_profile_b=$(uuidgen | tr '[:upper:]' '[:lower:]')
swift run ClaudeWebProbe login "$claude_profile_b"
swift run ClaudeWebProbe login "$claude_profile_a"
```

Jesse signs in to a different Claude account for profile B. The final profile A
run must return to the first account without authentication and without
changing profile B. The two windows from each profile must have valid,
account-specific values.

- [ ] **Step 5: Record the gate and clean up test profiles**

Append the date, source commit of the researched tracker
(`574eb3720c9b793ed9d1477861187f7c9c23b6e2`), macOS version, HTTP outcomes,
window shapes, and whether profile A persisted after profile B login. Do not
record identity or credential values.

Then run:

```bash
swift run ClaudeWebProbe delete "$claude_profile_a"
swift run ClaudeWebProbe delete "$claude_profile_b"
```

Expected: both identified WebKit stores are removed.

- [ ] **Step 6: Run full verification**

Run:

```bash
swift test
swift build --product ClaudeWebProbe
git diff --check
```

Expected: all tests and builds pass, and the diff check is clean.

- [ ] **Step 7: Commit**

```bash
git add Package.swift Sources/ClaudeWebProbe docs/provider-qualification.md
git commit -m "Qualify isolated Claude web sessions"
```

---

## Plan Self-Review

- The plan covers decoding, per-profile cookie isolation, Claude-shaped
  requests, SSO popup behavior, macOS 26 cookie observation gaps, provisional
  cleanup, two-account persistence, sanitized evidence, and test-store cleanup.
- The production provider migration remains out of scope until the live gate
  succeeds.
- All declared type names are used consistently across tasks.
- No placeholder steps or unspecified error-handling tasks remain.
