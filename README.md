# Agentic Usage Meter

Agentic Usage Meter is a macOS menu-bar app that shows coding-agent
subscription quota windows and balances across your accounts.

![Agentic Usage Meter showing synthetic quota windows](docs/images/usage-popover.png)

Built by [fsck.com](https://fsck.com).

## What it shows

The menu-bar panel and optional floating widget show the remaining quota and
reset times returned for each connected account. Collapsible sections keep
five-hour, weekly, monthly, and Extra Credits information readable when you
have several accounts.

The app displays only quota windows and balances returned by the provider. It
does not invent missing five-hour, weekly, monthly, or credit rows.

## Providers

Qualified providers:

- Claude — isolated browser session
- Codex — ChatGPT OAuth in your browser
- Kimi — device authorization

Experimental providers:

- MiniMax — Token Plan API key
- GitHub — device OAuth
- Factory — per-account API key
- OpenCode Go — isolated OpenCode session
- OpenCode Zen — isolated OpenCode session
- SuperGrok — Grok device OAuth

Antigravity is unavailable because its CLI uses the shared macOS Keychain,
which cannot isolate separate accounts.

Provider names and logos are trademarks of their respective owners; inclusion
does not imply endorsement. See the
[provider-mark attribution](Sources/UsageMeterUI/Resources/ProviderMarks/ATTRIBUTION.md).

## Accounts and privacy

Agentic Usage Meter has no application server: requests go directly from your
Mac to each provider. OAuth tokens and API keys are stored in account-scoped
Keychain items. Claude and OpenCode cookies stay in account-scoped WebKit
profiles. Cached usage is stored in Application Support.

The app has no analytics or telemetry.

![Synthetic account management in Agentic Usage Meter](docs/images/account-management.png)

## Install

When a public build is available, download the latest notarized app from
[GitHub Releases](https://github.com/obra/agentic-usage-meter/releases), move
it to Applications, and launch it.

## Build from source

Requirements: macOS 26 and Xcode 26 with Swift 6.2.

```sh
swift build --product AgenticUsageMeter
swift test
swift run AgenticUsageMeter --sample-data
```

`--sample-data` launches the app with synthetic values and a visible `SAMPLE
DATA` marker; it does not connect to an account.

For a locally signed app, run:

```sh
Scripts/build-and-run-local.sh
```

## Refresh behavior

The development build refreshes automatically no more often than once per
minute per provider account. Release builds use a ten-minute minimum.
Manual and on-demand refreshes share the same per-account limit, and provider
retry or backoff can make the interval longer.

## Provider diagnostics

Provider APIs and returned usage data can change. See the
[provider qualification notes](docs/provider-qualification.md) for each
provider's current qualification status, authentication surface, and known
data limitations.

## Release and updates

Published builds are direct downloads from the
[latest GitHub Release](https://github.com/obra/agentic-usage-meter/releases/latest).
The app checks the signed Sparkle feed automatically and asks for confirmation
before installing an update. Maintainers build, sign, notarize, verify, and
publish releases locally by following the [release guide](docs/releasing.md).

## License

Agentic Usage Meter is available under the [MIT License](LICENSE). See
[third-party notices](THIRD_PARTY_NOTICES.md) for incorporated notices.
