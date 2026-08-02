# OpenCode Profile Lifecycle Repair Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Release cached OpenCode WebKit profile loaders before account deletion so removed or re-added accounts cannot retain stale sessions.

**Architecture:** `OpenCodeProfileAuthCookieSource` remains the owner of per-account cookie loaders and gains an explicit eviction operation. `OpenCodeWebAccountUsageClient` invokes that eviction after deleting the provider credential but before asking WebKit to remove the profile, with a real persistent-profile regression proving the data store can be removed and recreated without its cookie.

**Tech Stack:** Swift 6.2, Swift Testing, WebKit persistent `WKWebsiteDataStore`, SwiftPM.

## Global Constraints

- Make the smallest lifecycle repair; do not redesign OpenCode authentication.
- Remove the cached loader before `AccountWebProfileStore.remove(accountID:)` begins.
- Keep credential removal before profile removal, matching the existing provider-adapter contract.
- Do not add a compatibility or retry workaround around retained WebKit stores.
- Tests must exercise loader ownership and a real persistent WebKit profile, not rendered source strings.
- Commit the repair separately before public-release work.

---

### Task 1: Evict cached OpenCode profile loaders during account removal

**Files:**
- Modify: `Sources/UsageMeterUI/Settings/OpenCodeWebAccountUsageClient.swift`
- Modify: `Tests/UsageMeterUITests/OpenCodeConnectionTests.swift`

**Interfaces:**
- Consumes: `AccountWebProfileStore.remove(accountID:) async throws` and the existing `OpenCodeProfileAuthCookieSource.authCookie(accountID:) async -> String?`.
- Produces: `OpenCodeProfileAuthCookieSource.evict(accountID:)` and `OpenCodeWebAccountUsageClient.EvictAuthCookieProfile`, invoked before `RemoveProfile`.

- [ ] **Step 1: Write a failing cache-ownership test**

Add a focused test beside `openCodeCookieSourceWarmsAColdProfile`:

```swift
@Test
@MainActor
func openCodeCookieSourceReleasesAnEvictedProfile() async {
    let accountID = UUID()
    var createdProfiles = 0
    weak var retainedProfile: TestOpenCodeCookieProfile?
    let source = OpenCodeProfileAuthCookieSource(
        retryDelays: [],
        profileFactory: { _ in
            createdProfiles += 1
            let profile = TestOpenCodeCookieProfile(responses: [[]])
            retainedProfile = profile
            return profile
        }
    )

    _ = await source.authCookie(accountID: accountID)
    #expect(createdProfiles == 1)
    #expect(retainedProfile != nil)

    source.evict(accountID: accountID)

    #expect(retainedProfile == nil)
    _ = await source.authCookie(accountID: accountID)
    #expect(createdProfiles == 2)
}
```

- [ ] **Step 2: Write a failing removal-order test**

Replace the current `removingOpenCodeAccountDeletesCredentialAndWebProfile` assertion with an event recorder that proves eviction precedes removal:

```swift
@Test
@MainActor
func removingOpenCodeAccountEvictsLoaderBeforeDeletingProfile()
    async throws
{
    let account = SubscriptionAccount(
        provider: .openCodeGo,
        displayName: "OpenCode",
        displayOrder: 0
    )
    let base = TestProviderAccountAdapter(provider: .openCodeGo)
    let lifecycle = OpenCodeProfileLifecycleRecorder()
    let adapter = OpenCodeWebAccountUsageClient(
        base: base,
        credentialStore: TestCredentialStore(),
        loadAuthCookie: { _ in nil },
        evictAuthCookieProfile: { profileID in
            #expect(profileID == account.id)
            lifecycle.record("evict")
        },
        removeProfile: { profileID in
            #expect(profileID == account.id)
            lifecycle.record("remove")
        }
    )

    try await adapter.removeAuthentication(for: account)

    #expect(await base.removedAccountIDs == [account.id])
    #expect(lifecycle.events == ["evict", "remove"])
}
```

Add a `@MainActor` test recorder class with `private(set) var events: [String]` and `record(_:)`. This avoids mutating a captured local from the `@Sendable` lifecycle closures.

- [ ] **Step 3: Run the focused tests and verify both fail for the missing API**

Run:

```bash
swift test --filter 'openCodeCookieSourceReleasesAnEvictedProfile|removingOpenCodeAccountEvictsLoaderBeforeDeletingProfile'
```

Expected: compilation fails because `evict(accountID:)` and `evictAuthCookieProfile` do not exist.

- [ ] **Step 4: Add the minimal eviction interface and implementation**

In `OpenCodeWebAccountUsageClient`, add:

```swift
public typealias EvictAuthCookieProfile =
    @MainActor @Sendable (UUID) -> Void

private let evictAuthCookieProfile: EvictAuthCookieProfile
```

Extend the initializer immediately after `loadAuthCookie`:

```swift
evictAuthCookieProfile: EvictAuthCookieProfile? = nil,
```

When a custom `loadAuthCookie` is supplied, store the custom eviction closure or a no-op. When the default source is constructed, bind both closures to the same source:

```swift
if let loadAuthCookie {
    self.loadAuthCookie = loadAuthCookie
    self.evictAuthCookieProfile =
        evictAuthCookieProfile ?? { _ in }
} else {
    let source = OpenCodeProfileAuthCookieSource()
    self.loadAuthCookie = {
        await source.authCookie(accountID: $0)
    }
    self.evictAuthCookieProfile = {
        source.evict(accountID: $0)
    }
}
```

Add the source operation:

```swift
func evict(accountID: UUID) {
    profiles[accountID] = nil
}
```

Call it before persistent profile removal:

```swift
try await base.removeAuthentication(for: account)
evictAuthCookieProfile(account.id)
try await removeProfile(account.id)
```

- [ ] **Step 5: Run the focused tests and verify they pass**

Run:

```bash
swift test --filter 'openCodeCookieSourceReleasesAnEvictedProfile|removingOpenCodeAccountEvictsLoaderBeforeDeletingProfile'
```

Expected: both tests pass.

- [ ] **Step 6: Add a real WebKit profile recreation regression**

Add a test-only `RetainedOpenCodeCookieProfile` that owns `AccountWebProfileStore`, can set and read cookies through its real `WKHTTPCookieStore`, and implements `OpenCodeProfileCookieLoading`. Then add:

```swift
@Test
@MainActor
func evictedOpenCodeProfileCanBeRemovedAndRecreatedWithoutCookies()
    async throws
{
    let accountID = UUID()
    weak var retainedProfile: RetainedOpenCodeCookieProfile?
    let source = OpenCodeProfileAuthCookieSource(
        retryDelays: [],
        profileFactory: { id in
            let profile = RetainedOpenCodeCookieProfile(accountID: id)
            retainedProfile = profile
            return profile
        }
    )
    let cookie = try #require(
        HTTPCookie(
            properties: [
                .name: "auth",
                .value: "session-to-delete",
                .domain: "opencode.ai",
                .path: "/",
            ]
        )
    )

    _ = await source.authCookie(accountID: accountID)
    var profile: RetainedOpenCodeCookieProfile? =
        try #require(retainedProfile)
    await profile?.setCookie(cookie)
    #expect(await profile?.cookies().contains { $0.name == "auth" } == true)
    profile = nil

    source.evict(accountID: accountID)
    #expect(retainedProfile == nil)
    try await AccountWebProfileStore.remove(accountID: accountID)

    var recreated: RetainedOpenCodeCookieProfile? =
        RetainedOpenCodeCookieProfile(accountID: accountID)
    #expect(await recreated?.cookies().allSatisfy { $0.name != "auth" } == true)
    recreated = nil
    try await AccountWebProfileStore.remove(accountID: accountID)
}
```

The helper must bridge `setCookie` and `getAllCookies` with checked continuations; it must not mock the profile store.

- [ ] **Step 7: Run the OpenCode and WebKit profile suites**

Run:

```bash
swift test --filter openCode
swift test --filter accountStoresRemainIndependentWhenOneIsRemoved
```

Expected: all selected tests pass, including real persistent-store deletion.

- [ ] **Step 8: Run the complete suite**

Run:

```bash
swift test
```

Expected: all tests pass with no retained-profile timeout.

- [ ] **Step 9: Commit the lifecycle repair**

```bash
git status --short
git add Sources/UsageMeterUI/Settings/OpenCodeWebAccountUsageClient.swift Tests/UsageMeterUITests/OpenCodeConnectionTests.swift
git commit -m "Release OpenCode profiles before account deletion" -m "Evict the per-account WebKit cookie loader before removing its persistent data store. Cover cache recreation, removal ordering, and real profile deletion so removed accounts cannot retain or inherit stale OpenCode sessions."
```
