# Agentic Usage Meter

Agentic Usage Meter is a macOS 26 menu-bar app for watching subscription quota
windows across multiple coding-agent accounts. The optional floating widget
aligns comparable five-hour windows on a shared ten-hour axis and weekly
windows on a shared fourteen-day axis.

The app displays only windows actually returned by a provider. A provider that
currently returns weekly usage but no five-hour usage gets a weekly row only.

## Develop

Requirements:

- macOS 26
- Xcode 26 with Swift 6.2

Build and test:

```sh
swift build --product AgenticUsageMeter
swift test
swift run AgenticUsageMeter --sample-data
```

`--sample-data` uses synthetic acceptance values and marks the interface
`SAMPLE DATA`; it never represents a connected subscription.

The app runs as a menu-bar accessory and does not appear in the Dock. Open
Settings from the menu-bar panel to add accounts:

- Claude opens an embedded browser. Every account gets an independent
  persistent WebKit profile, so Claude sessions do not replace each other.
- Codex opens the regular browser for PKCE OAuth, shows the authenticated
  identity before saving, and rejects a subscription already connected.
- Kimi opens its device-authorization page in the regular browser and displays
  the user code and expiry in Settings.

Development builds also expose experimental account flows for:

- MiniMax Token Plan API keys;
- GitHub Copilot device OAuth;
- SuperGrok device OAuth;
- OpenCode Go and Zen isolated workspace sessions; and
- Factory API keys.

Release builds hide experimental providers until two real accounts pass the
restart, refresh, reconnect, dashboard-isolation, and deletion qualification
gate. Antigravity remains unavailable because its CLI stores authentication in
the shared macOS Keychain; changing `$HOME` does not isolate accounts.

OAuth tokens and API keys are stored as separate account-scoped Keychain
items. Claude and OpenCode cookies remain in their identified WebKit data
stores and are not copied into application settings or Keychain. Removing an
account deletes its credential or complete WebKit profile.

Usage is cached on disk and shown immediately at launch. Scheduled, manual,
menu-bar, and widget demand share the same per-account refresher. No account
usage request is started less than ten minutes after that account's preceding
request.

## Assemble a local app

```sh
Scripts/assemble-app.sh
codesign --force --deep --sign - "build/Agentic Usage Meter.app"
codesign --verify --deep --strict --verbose=2 \
  "build/Agentic Usage Meter.app"
open "build/Agentic Usage Meter.app"
```

This produces `build/Agentic Usage Meter.app`. An ad-hoc signature is suitable
for local verification only; it is not notarized distribution evidence.

## Sign and notarize

Create a notarytool Keychain profile outside this repository, then provide the
exact existing Developer ID Application identity and profile name:

```sh
DEVELOPER_ID_APPLICATION="Developer ID Application: Example (TEAMID)" \
NOTARYTOOL_PROFILE="agentic-usage-meter" \
Scripts/sign-and-notarize.sh
```

The script assembles a fresh release, signs with the hardened runtime, submits
a zip to Apple's notary service, staples the accepted ticket, and verifies the
signature, Gatekeeper assessment, and staple. It never creates identities or
stores signing credentials.

The app deliberately has no App Sandbox entitlement. Direct distribution,
Keychain access, provider networking, WebKit profiles, and the localhost Codex
OAuth callback therefore do not require a sandbox entitlement file.
