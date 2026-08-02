# Public Release and Updates Design

**Date:** 2026-08-01

**Status:** Approved

## Context

Agentic Usage Meter, made by Jesse Vincent, is ready to move from a local development repository to a public macOS project under Jesse's `obra` GitHub account. The public release needs to explain the product clearly, show the real interface without exposing account data, use the `com.fsck` technical namespace, list Jesse's personal homepage at `https://fsck.com`, and provide a secure update path for direct-distribution builds.

The existing `obra/winby` project supplies the reference user experience: automatic update checks, explicit confirmation before installation, and a manual **Check for Updates...** action. Its release workflow is useful precedent, but Agentic Usage Meter will use Sparkle's current appcast tooling and Keychain-backed EdDSA key instead of hand-writing the feed or copying the private key into a temporary file.

## Goals

- Publish the complete repository publicly as `obra/agentic-usage-meter` under the MIT license.
- Present the app with a concise product-focused README and synthetic screenshots.
- Change the product namespace from the previous namespace to `com.fsck.agentic-usage-meter` everywhere it identifies this app.
- Add signed Sparkle updates for direct-distribution builds.
- Check for updates automatically while requiring confirmation before installation.
- Automate local release construction, signing, notarization, appcast generation, and GitHub upload as far as existing credentials allow.
- Preserve the existing release verification, privacy, and provider-qualification boundaries.

## Non-goals

- App Store distribution.
- Silent installation of updates.
- A custom update service or telemetry backend.
- Publishing real account names, identities, quotas, cookies, tokens, or organization data.
- Treating experimental providers as qualified.
- Copying or retrieving secret values from another GitHub repository.

## Public repository and README

The repository will be public at `https://github.com/obra/agentic-usage-meter`, with `main` as its default branch and Jesse's personal homepage, `https://fsck.com`, as its homepage. Jesse Vincent is the app's author and maker; the root MIT `LICENSE` will name him as the copyright holder.

The README will lead with what the app does and the primary screenshot. It will then cover:

- remaining quota and reset-time visualization across multiple accounts;
- qualified, experimental, and unavailable providers without overstating support;
- the menu-bar popover, optional floating widget, collapsible summaries, signed-in dashboards, and extra-credit balances;
- credential isolation, Keychain and WebKit storage, provider-direct networking, and the absence of an application server;
- release and development requirements;
- local build, test, and signed-app commands;
- the one-minute development and ten-minute release refresh floors;
- direct-download updates and the explicit provider-response-change caveat.

The README will attribute the app to Jesse Vincent and link to his personal homepage, `https://fsck.com`, as well as the MIT license, provider qualification notes, and the GitHub release page. It will not use an email address as public attribution.

## Screenshots and privacy

The README will include at least two screenshots:

1. the menu-bar usage popover with expanded quota windows and Extra Credits;
2. account management or the compact collapsed-shelf treatment.

Every screenshot will come from the existing `--sample-data` launch mode. The sample state will use generic account labels and synthetic quotas only. It will not contain Jesse's name, `fsck.com`, Prime Radiant, email addresses, real provider identities, or actual subscription values. The visible **SAMPLE DATA** marker remains present so screenshots cannot be mistaken for connected usage.

Screenshots will be captured as app-window content rather than an entire desktop, inspected at full resolution, stored under `docs/images/`, and referenced with relative paths so GitHub renders them from the repository.

Before publication, tracked files and reachable Git history will be scanned for credential patterns and unintended private data. The audit reports paths and categories, never discovered secret values. Any sensitive history blocks publication until it is removed with Jesse's explicit approval.

## Product namespace

The bundle identifier, logging subsystem, main credential service, probe credential service, tests, and current implementation documentation will use the reverse-DNS namespace `com.fsck.agentic-usage-meter`.

This is a clean pre-release identity correction rather than a permanent compatibility layer. macOS may require one final round of Keychain authorization because the bundle identifier changes. Once the app is consistently Developer ID-signed under the new identifier, subsequent local and released builds retain that stable identity.

No code will silently read both old and new Keychain namespaces. Existing account state remains on disk, and credentials that macOS does not grant to the new identity surface through the current reconnect flow rather than an invented migration.

## Sparkle integration

The app will use the current Sparkle 2 Swift Package Manager product, pinned to the reviewed release used during implementation. The assembled application bundle will copy and sign Sparkle's framework and helper components inside-out before signing the outer app.

A small app-lifetime updater owner will retain `SPUStandardUpdaterController`. Proper application bundles with a configured feed start the updater after launch. Bare `swift run` and test hosts without the required Info.plist values leave the updater disabled.

The application Info.plist will contain:

- `SUFeedURL` pointing to the `appcast.xml` asset on the latest `obra/agentic-usage-meter` GitHub release;
- `SUPublicEDKey` containing the generated EdDSA public key;
- automatic update checks enabled;
- automatic installation disabled.

The menu-bar footer or Settings UI will expose **Check for Updates...**. Sparkle's standard user driver presents release information and asks before installing an available update. The app does not build a second update interface.

## Update signing and feed

Sparkle's `generate_keys` tool will create the update signing identity once. The private EdDSA key stays in Jesse's login Keychain; only the public key is committed. Losing that private key is a release-blocking incident and is documented accordingly.

The release archive is signed with the stable Developer ID Application identity, notarized, and stapled before it receives its Sparkle signature. Sparkle's supported `generate_appcast` tooling produces the feed from the final distributable archive and release notes. The generated enclosure URL points to the immutable GitHub release asset.

The first public release establishes the feed and signing keys. Later releases must monotonically increase both `CFBundleVersion` and the user-facing version. The release command rejects a mismatched tag, dirty worktree, missing signing identity, missing notary profile, absent Sparkle key, failed notarization, or failed verification before uploading anything.

## Release automation

The authoritative initial path is a local release command because this Mac already has the Developer ID identity and can use an existing notarytool Keychain profile without exporting secrets. The command will:

1. verify the version and clean worktree;
2. run tests and assemble the release app;
3. sign Sparkle's nested code and the application;
4. notarize, staple, and verify the archive;
5. generate release notes and the Sparkle appcast from the final archive;
6. create the GitHub release and upload the archive plus `appcast.xml`;
7. fetch the uploaded feed and release asset and verify their public availability.

Repository settings, release metadata, and non-secret GitHub configuration will be created automatically. GitHub does not expose existing Winby secret values, so any future Actions-based release workflow must receive its own certificate, notarization, and Sparkle secrets manually. An unusable workflow will not be presented as complete automation.

## OpenCode lifecycle release gate

The current OpenCode qualification repair introduced a cached WebKit profile loader. Account removal must evict that loader before deleting its `WKWebsiteDataStore`; otherwise WebKit can retain the profile and its cookies for the rest of the process.

Before public release, the cookie source will expose account eviction, the removal path will release the loader before deleting the profile, and regression coverage will warm a profile, remove the account, and prove the profile can be recreated without inheriting its session. This is part of publication readiness, not a new public feature.

## Verification

Automated and mechanical verification will cover:

- the exact `com.fsck.agentic-usage-meter` bundle identifier and absence of live previous-namespace product identifiers;
- the updater's enabled and disabled configuration paths;
- the presence and shape of Sparkle feed and public-key values in assembled releases;
- Sparkle framework embedding, hardened-runtime signing, notarization, staple, and Gatekeeper assessment;
- monotonically increasing release versions and immutable release URLs;
- OpenCode profile eviction and clean recreation;
- the full Swift test suite;
- README links, image paths, and synthetic-data assertions;
- repository and reachable-history secret scanning.

Live acceptance will verify that a signed installed build starts automatic checks, **Check for Updates...** reaches Sparkle, an available test update requires confirmation, canceling leaves the current app untouched, and accepting a valid update installs and relaunches the signed successor. Publication is complete only after the GitHub README, screenshots, license, release assets, and appcast render or download from their public URLs.

## Rejected alternatives

- **Copy Winby's release workflow verbatim:** it hand-builds appcast XML and handles the Sparkle private key through a temporary file; current Sparkle tooling provides a safer and less brittle path.
- **Silent updates:** removes meaningful user control and contradicts Jesse's explicit confirmation choice.
- **Custom GitHub API updater:** duplicates Sparkle's signature, installation, rollback, and user-interface work.
- **Keep the previous namespace as a legacy Keychain namespace:** leaves the product identity knowingly wrong and adds indefinite pre-release compatibility baggage.
- **Real-data screenshots with redaction:** redaction can miss PII and makes repeatable documentation harder than capturing the existing synthetic mode.
- **Publish before the history audit:** a clean current tree is insufficient if a reachable commit contains a credential.
