# Changelog

## 0.2.2 - 2026-08-06

### Fixed

- Removing a Claude account works again. Removal previously gave up
  whenever the account's isolated browser profile was still open
  anywhere in the app and silently did nothing; deletion now releases
  the profile, retries around WebKit's asynchronous teardown, verifies
  the profile is gone, and shows an error if it still fails.
- Claude accounts now connect to the account's chat organization.
  Accounts whose Anthropic Console organization was listed first were
  bound to it and could never load usage data.
- Connecting a Claude account whose usage response the app cannot read
  now fails with an explanation instead of saving an account that never
  shows data.

### Changed

- Adding an account is now a two-step wizard: pick a provider, then
  sign in with the full sheet available to the login page.
- Claude connection and refresh failures are now logged to the system
  log (subsystem `com.fsck.agentic-usage-meter`) with structural
  details only, so bug reports can include diagnostics without exposing
  account data.

## 0.2.1 - 2026-08-04

### Changed

- Releases are now built, signed, notarized, and published from GitHub
  Actions when a version tag is pushed, with the local release path kept as
  a fallback. This release is otherwise identical to 0.2.0.

## 0.2.0 - 2026-08-04

### Added

- Experimental Z.ai GLM Coding Plan connections using the account's Coding
  Plan API key.
- Experimental Xiaomi MiMo Token Plan connections using an isolated browser
  session, with the monthly bundle shown as remaining tokens.

### Changed

- Replaced the menu bar glyph with an open gauge so it no longer resembles
  Time Machine's clock icon.

### Fixed

- Claude usage refreshes no longer fail on accounts whose reset timestamps
  include fractional seconds.

## 0.1.1 - 2026-08-02

### Added

- First downloadable public release of the multi-provider macOS menu-bar usage
  meter.
- Qualified account connections for Claude, Codex, and Kimi, plus experimental
  connections for MiniMax, GitHub, Factory, OpenCode Go, OpenCode Zen, and
  SuperGrok.
- Collapsible quota-window and balance sections in the menu-bar panel and
  optional floating widget.
- Privacy-preserving local credential storage and direct provider requests,
  with no application server, analytics, or telemetry.
- Confirmation-based Sparkle update checks from signed GitHub Release assets.
- A provider-request link in the add-account screen for requesting additional
  integrations.

### Fixed

- Corrected the public author attribution to Jesse Vincent.
- Hardened release-feed validation against metadata split across separate
  items.

## 0.1.0 - 2026-08-01

### Added

- First public release of the multi-provider macOS menu-bar usage meter.
- Qualified account connections for Claude, Codex, and Kimi, plus experimental
  connections for MiniMax, GitHub, Factory, OpenCode Go, OpenCode Zen, and
  SuperGrok.
- Collapsible quota-window and balance sections in the menu-bar panel and
  optional floating widget.
- Privacy-preserving local credential storage and direct provider requests,
  with no application server, analytics, or telemetry.
- Confirmation-based Sparkle update checks from signed GitHub Release assets.
