# Public Identity and README Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prepare Agentic Usage Meter for public release with the corrected `fsck.com` product identity, MIT licensing, a product-focused README, and repeatable screenshots containing only synthetic data.

**Architecture:** Keep public documentation and screenshots rooted in the existing sample-data path rather than inventing a documentation-only UI. Change live reverse-DNS identifiers cleanly before release, validate sample accounts structurally, capture only app windows, and block publication on any credible secret found in tracked history.

**Tech Stack:** Swift 6.2, Swift Testing, SwiftUI/AppKit, Git, Gitleaks, GitHub-flavored Markdown, macOS screenshot tooling.

## Global Constraints

- The public repository target is `obra/agentic-usage-meter`; repository creation occurs in the Sparkle/publication plan after all release code is ready.
- The public homepage is `https://fsck.com`.
- The project is MIT licensed with copyright held by Jesse Vincent.
- Every live product identifier uses `com.fsck.agentic-usage-meter`; do not add a legacy namespace fallback.
- Screenshots must come from `--sample-data`, visibly say **SAMPLE DATA**, and contain no real names, domains, emails, identities, organizations, or quotas.
- Do not rewrite Git history automatically. A credible credential finding requires stopping for Jesse's approval.
- Provider claims must match `ProviderCatalog.live` and `docs/provider-qualification.md` at implementation time.
- Documentation-only changes use rendered/manual verification instead of brittle source-string unit tests.

---

### Task 1: Correct the product namespace

**Files:**
- Modify: `Resources/Info.plist`
- Modify: `Sources/UsageMeterCore/Credentials/KeychainCredentialStore.swift`
- Modify: `Sources/UsageMeterProbe/UsageMeterProbe.swift`
- Modify: `Sources/UsageMeterCore/Providers/SuperGrok/SuperGrokUsageDecoder.swift`
- Modify: `Tests/UsageMeterCoreTests/ReleaseConfigurationTests.swift`
- Modify: `docs/superpowers/plans/2026-07-29-agentic-usage-meter-implementation.md`

**Interfaces:**
- Consumes: the existing bundle, Keychain service, probe service, and logging subsystem strings.
- Produces: `com.fsck.agentic-usage-meter`, `com.fsck.agentic-usage-meter.credentials`, and `com.fsck.agentic-usage-meter.probe.credentials` as the only live product namespaces.

- [ ] **Step 1: Change the release-contract test first**

Update the existing expectation in `applicationBundleDeclaresMenuBarReleaseContract`:

```swift
#expect(
    plist["CFBundleIdentifier"] as? String
        == "com.fsck.agentic-usage-meter"
)
```

Add a direct public contract for the main credential service:

```swift
import UsageMeterCore

@Test
func keychainServiceUsesTheFsckProductNamespace() {
    #expect(
        KeychainCredentialStore.defaultService
            == "com.fsck.agentic-usage-meter.credentials"
    )
}
```

- [ ] **Step 2: Run the focused tests and verify they fail**

Run:

```bash
swift test --filter 'applicationBundleDeclaresMenuBarReleaseContract|keychainServiceUsesTheFsckProductNamespace'
```

Expected: both tests fail because live configuration still uses `com.jesse`.

- [ ] **Step 3: Replace live reverse-DNS identifiers**

Apply these exact values:

```text
CFBundleIdentifier: com.fsck.agentic-usage-meter
main Keychain service: com.fsck.agentic-usage-meter.credentials
probe Keychain service: com.fsck.agentic-usage-meter.probe.credentials
SuperGrok Logger subsystem: com.fsck.agentic-usage-meter
```

Update the two historical implementation-plan statements that describe the current credential service and bundle contract. Do not rewrite old commit history.

- [ ] **Step 4: Prove no live `com.jesse` namespace remains**

Run:

```bash
rg -n 'com\.jesse' Sources Tests Resources Scripts Package.swift README.md
```

Expected: no matches. If a historical design discussion intentionally names the rejected identifier, change the wording to “the previous namespace” rather than retaining the live string.

- [ ] **Step 5: Run the focused tests and the assembled-plist check**

Run:

```bash
swift test --filter 'applicationBundleDeclaresMenuBarReleaseContract|keychainServiceUsesTheFsckProductNamespace'
Scripts/assemble-app.sh
plutil -extract CFBundleIdentifier raw 'build/Agentic Usage Meter.app/Contents/Info.plist'
```

Expected: tests pass and `plutil` prints `com.fsck.agentic-usage-meter`.

- [ ] **Step 6: Commit the namespace correction**

```bash
git status --short
git add Resources/Info.plist Sources/UsageMeterCore/Credentials/KeychainCredentialStore.swift Sources/UsageMeterProbe/UsageMeterProbe.swift Sources/UsageMeterCore/Providers/SuperGrok/SuperGrokUsageDecoder.swift Tests/UsageMeterCoreTests/ReleaseConfigurationTests.swift docs/superpowers/plans/2026-07-29-agentic-usage-meter-implementation.md
git commit -m "Use the fsck.com product namespace" -m "Correct the bundle identifier, Keychain services, logging subsystem, release contract, and current implementation documentation from the pre-release com.jesse namespace to com.fsck. This is an intentional clean identity transition without a permanent compatibility layer."
```

---

### Task 2: Add the MIT license and public product README

**Files:**
- Create: `LICENSE`
- Modify: `README.md`
- Modify: `THIRD_PARTY_NOTICES.md` only if the current provider-mark attribution needs a clearer README pointer; Sparkle attribution belongs to the later Sparkle task.

**Interfaces:**
- Consumes: `ProviderCatalog.live`, `docs/provider-qualification.md`, and existing build/sign/notarize scripts.
- Produces: the complete GitHub landing-page prose; Task 3 adds screenshot references atomically with the image files.

- [ ] **Step 1: Add the standard MIT license**

Create `LICENSE` with the unmodified MIT grant and disclaimer, beginning:

```text
MIT License

Copyright (c) 2026 Jesse Vincent
```

Use the standard SPDX MIT text through “SOFTWARE.” without adding project-specific conditions.

- [ ] **Step 2: Rewrite the README around the product**

Use this section order:

```markdown
# Agentic Usage Meter

One-sentence macOS menu-bar product description.

## What it shows
## Providers
## Accounts and privacy
## Install
## Build from source
## Refresh behavior
## Provider diagnostics
## Release and updates
## License
```

The provider section must derive its labels from the live catalog:

- Qualified: Claude, Codex, Kimi.
- Experimental: MiniMax, GitHub, Factory, OpenCode Go, OpenCode Zen, SuperGrok.
- Unavailable: Antigravity, with the shared-Keychain isolation reason.

State that the app displays only quota windows and balances returned by the provider; it does not invent missing five-hour, weekly, monthly, or credit rows.

The privacy section must state:

- no application server;
- provider-direct requests;
- OAuth tokens/API keys in account-scoped Keychain items;
- Claude/OpenCode cookies in account-scoped WebKit profiles;
- cached usage in Application Support;
- no analytics or telemetry.

Link the author/homepage as `[fsck.com](https://fsck.com)` and never publish an email address.

- [ ] **Step 3: Verify documentation claims against live code**

Run:

```bash
sed -n '65,275p' Sources/UsageMeterCore/Providers/ProviderCatalog.swift
sed -n '1,260p' docs/provider-qualification.md
sed -n '1,140p' Sources/UsageMeterCore/Refresh/RefreshPolicy.swift
```

Expected: every provider state, authentication description, and one-/ten-minute refresh statement in README has a matching live source. Correct the README if code differs; do not “correct” code to make prose true.

- [ ] **Step 4: Validate Markdown and links locally**

Run:

```bash
git diff --check
test -s LICENSE
test -s README.md
if rg -n 'docs/images/' README.md; then
  echo 'Screenshot references must be committed with their image files.' >&2
  exit 1
fi
```

Expected: clean whitespace and no screenshot path before the image files exist. Task 3 adds both references and assets in one commit.

- [ ] **Step 5: Commit the license and README text**

```bash
git status --short
git add LICENSE README.md THIRD_PARTY_NOTICES.md
git commit -m "Document Agentic Usage Meter for public release" -m "Add the MIT license and replace the development-oriented README with a product-focused guide covering provider status, privacy boundaries, account isolation, refresh behavior, direct distribution, and the reserved synthetic screenshot locations."
```

If `THIRD_PARTY_NOTICES.md` did not change, omit it from `git add`.

---

### Task 3: Prove sample-data privacy and capture public screenshots

**Files:**
- Modify: `Sources/AgenticUsageMeter/AgenticUsageMeterApp.swift` only if current sample account labels need further anonymization.
- Modify: `Tests/UsageMeterUITests/AppModelTests.swift`
- Create: `docs/images/usage-popover.png`
- Create: `docs/images/account-management.png`

**Interfaces:**
- Consumes: `AppEnvironment.sampleState(showWidget:)`, `--sample-data`, menu-bar popover, section collapse controls, and Settings.
- Produces: two inspected PNG assets referenced by README.

- [ ] **Step 1: Add a structured sample-data privacy test**

Add beside `sampleDataIncludesKimiFiveHourWindow`:

```swift
@Test
func sampleDataContainsNoAuthenticatedIdentitiesOrOrganizations() {
    let state = AppEnvironment.sampleState(showWidget: false)
    let allowedNames = Set([
        "Work",
        "Personal",
        "Kimi",
        "Factory",
    ])

    #expect(state.accounts.allSatisfy {
        allowedNames.contains($0.displayName)
    })
    #expect(state.accounts.allSatisfy {
        $0.authenticatedIdentity == nil
            && $0.claudeProfileID == nil
            && $0.claudeOrganizationID == nil
    })
}
```

This asserts structured fields rather than searching rendered JSON or screenshots.

- [ ] **Step 2: Run the sample-state tests**

Run:

```bash
swift test --filter 'sampleDataContainsNoAuthenticatedIdentitiesOrOrganizations|sampleDataIncludesKimiFiveHourWindow'
```

Expected: both pass. If the privacy test fails, replace only the offending sample labels or identity fields with generic values and rerun it.

- [ ] **Step 3: Build and launch the signed sample app**

Run:

```bash
CONFIGURATION=release Scripts/build-and-run-local.sh
pkill -x AgenticUsageMeter || true
open -na 'build/Agentic Usage Meter.app' --args --sample-data
```

Expected: a Developer ID-signed menu-bar app launches with no real state or credential access.

- [ ] **Step 4: Add the screenshot references with the assets**

Insert the hero image immediately after the opening description:

```markdown
![Agentic Usage Meter showing synthetic quota windows](docs/images/usage-popover.png)
```

Add the account-management image in the Accounts and Privacy section:

```markdown
![Synthetic account management in Agentic Usage Meter](docs/images/account-management.png)
```

- [ ] **Step 5: Capture the expanded popover**

Use the computer-use skill to open the menu-bar panel, expand the five-hour, weekly, monthly, and Extra Credits sections, and confirm the **SAMPLE DATA** badge is visible. Capture only the popover window at native resolution as:

```text
docs/images/usage-popover.png
```

The screenshot must not include the desktop, menu-bar account icons, browser tabs, Settings windows with real state, or any other application.

- [ ] **Step 6: Capture account management from the same sample process**

Open Settings from the sample popover and capture only the account-management window as:

```text
docs/images/account-management.png
```

The visible rows must contain only the sample account labels. Do not launch the production process to obtain this image.

- [ ] **Step 7: Inspect both images at original resolution**

Use the image viewer on both files and verify:

- **SAMPLE DATA** is legible in the product screenshot;
- no name, email, domain, organization, token, browser chrome, or unrelated notification appears;
- quota labels and bars are sharp at README scale;
- no cursor obscures text;
- the two images have distinct useful content.

If either image fails, delete only that exact PNG, recapture it, and inspect again.

- [ ] **Step 8: Verify the README image paths and PNG metadata**

Run:

```bash
file docs/images/usage-popover.png docs/images/account-management.png
test -s docs/images/usage-popover.png
test -s docs/images/account-management.png
rg -n 'docs/images/(usage-popover|account-management)\.png' README.md
git diff --check
```

Expected: both are non-empty PNG images and README references their exact relative paths.

- [ ] **Step 9: Commit the synthetic screenshot contract and assets**

```bash
git status --short
git add Sources/AgenticUsageMeter/AgenticUsageMeterApp.swift Tests/UsageMeterUITests/AppModelTests.swift docs/images/usage-popover.png docs/images/account-management.png README.md
git commit -m "Add privacy-safe product screenshots" -m "Prove sample accounts contain no authenticated identities or Claude organization identifiers, then document the product with native-resolution menu-bar and account-management captures generated exclusively from visibly marked synthetic data."
```

If `AgenticUsageMeterApp.swift` did not change, omit it from `git add`.

---

### Task 4: Audit the repository before it becomes public

**Files:**
- No repository files should change unless the audit finds a real issue.
- Temporary redacted report: `/tmp/agentic-usage-meter-gitleaks.json` (delete after review).

**Interfaces:**
- Consumes: all tracked files and all commits reachable from local refs.
- Produces: a go/no-go publication decision; it never produces a committed secret report.

- [ ] **Step 1: Install the audit tool if needed**

Run:

```bash
command -v gitleaks >/dev/null || brew install gitleaks
gitleaks version
```

Expected: a current Gitleaks executable is available.

- [ ] **Step 2: Scan reachable Git history with redaction enabled**

Run:

```bash
gitleaks git --redact --report-format json --report-path /tmp/agentic-usage-meter-gitleaks.json .
```

Expected: exit 0 and an empty report. If it exits nonzero, inspect only redacted rule IDs, commit IDs, and file paths:

```bash
jq -r '.[] | [.RuleID, .Commit, .File] | @tsv' /tmp/agentic-usage-meter-gitleaks.json
```

Do not print `Secret`, `Match`, or unredacted line content. Classify fixtures separately from live credentials. A credible credential requires stopping and asking Jesse before any history rewrite.

- [ ] **Step 3: Check known private and obsolete product markers**

Run:

```bash
rg -n -i 'jesse\.com' --glob '!.git/**' --glob '!.build/**' --glob '!build/**' .
rg -n 'com\.jesse' Sources Tests Resources Scripts Package.swift README.md
```

Expected: no live namespace or incorrect-domain match. Gitleaks is the authoritative credential and private-key scan. Mentions of Jesse's name in copyright and the approved design documents are expected; screenshots must contain none.

- [ ] **Step 4: Run the full mechanical release preflight**

Run:

```bash
swift test
git diff --check
git status --short --branch
```

Expected: all tests pass and the worktree is clean.

- [ ] **Step 5: Remove the temporary audit report**

Run:

```bash
rm -f /tmp/agentic-usage-meter-gitleaks.json
```

Expected: no credential report remains on disk or enters Git.
