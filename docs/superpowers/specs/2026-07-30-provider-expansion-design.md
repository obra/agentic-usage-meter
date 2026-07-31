# Provider Expansion Design

**Date:** 2026-07-30

**Status:** Implemented; real-provider qualification pending

**Target:** Provider architecture, account connection, refresh, diagnostics,
and account dashboards

## Summary

Expand Agentic Usage Meter from Claude, Codex, and Kimi to additional
quota-bearing coding products without turning authentication, credentials, and
Settings into provider-wide switch statements.

The initial expansion targets:

- GitHub Copilot;
- SuperGrok;
- Google Antigravity;
- Factory;
- OpenCode Go;
- OpenCode Zen;
- MiniMax Token Plan.

A supported product is a distinct subscription, allowance, or credit pool that
can report remaining usage. A client or model vendor name is not sufficient by
itself. Generic OpenCode is therefore not a provider; OpenCode Go and OpenCode
Zen are separate providers because they own separate quota and balance pools.
SuperGrok and xAI API billing are also separate products. This design includes
SuperGrok and does not silently combine it with xAI API spend.

## Goals

- Add providers through a compile-time catalog and small typed adapters.
- Preserve multiple independently authenticated accounts for every provider.
- Normalize timed quota windows and balances without inventing comparable data.
- Keep the ten-minute provider-contact floor global and testable.
- Open an isolated in-app provider dashboard when the provider supports it.
- Provide a native detail view and system-browser fallback when embedded
  authentication is blocked.
- Keep credentials local in Keychain, cached normalized usage in Application
  Support, and provider traffic direct from the Mac.
- Ship only providers that pass real multi-account qualification.

## Non-Goals

- A runtime plugin or third-party provider SDK.
- Importing every API configured in a coding client.
- Cloud credential sync, telemetry, or a relay service.
- Deriving quota from local token counts when the provider exposes no
  authoritative remaining-usage value.
- Showing mock, estimated, or synthetic windows in release builds.
- Treating a provider dashboard login as equivalent to API or CLI
  authentication.

## Provider Catalog

Replace provider-specific UI branching with a compile-time
`ProviderDefinition` catalog. The catalog is the single source for:

- stable provider ID;
- display name, color, and icon;
- release state;
- connection description and strategy;
- supported quota presentations;
- account dashboard strategy;
- concrete adapter.

Provider IDs are stable string-backed values rather than the source of
exhaustive UI switches. Provider order comes from the catalog. Provider-specific
behavior remains compiled and typed; this is not a dynamic plugin system.

Each definition has a release state:

- `qualified`, visible in release and development builds;
- `experimental`, visible only in development builds;
- `unavailable`, retained in the qualification matrix but absent from Add
  Account.

The Settings provider picker, account sections, timeline ordering, help text,
and dashboard actions all read the catalog. Adding a provider should require a
definition and adapter, not edits to unrelated exhaustive switches.

## Adapter Boundary

Each provider adapter owns:

- authentication or credential capture;
- provider identity and billing-scope discovery;
- credential refresh;
- usage retrieval and normalization;
- provider-specific diagnostics;
- account cleanup.

The shared application owns:

- account persistence and ordering;
- Keychain record addressing;
- refresh eligibility and concurrency;
- cached snapshots;
- common connection and error presentation;
- quota rendering;
- account dashboard windows.

The adapter receives an account ID and resolves its own credential type from
the account's Keychain record. The core account model does not grow a central
credential enum containing every provider payload.

Connection strategy is descriptive metadata used by the shared Add Account
flow:

- external-browser OAuth;
- API-key entry;
- isolated vendor-CLI profile;
- isolated WebKit session.

The adapter still implements the strategy. The shared UI does not attempt to
construct provider authorization URLs or decode provider credentials.

## Account Identity and Isolation

An account's provider identity key is:

```text
provider subject + billing scope
```

Email is display metadata, not identity. The billing scope distinguishes
separate personal, organization, enterprise, or workspace pools owned by the
same provider login.

Every saved account receives:

- an independent Keychain record;
- an independent CLI home/configuration root when the adapter is CLI-backed;
- an independent persistent WebKit data-store identifier when the provider
  uses or offers an embedded dashboard.

A CLI-backed provider is not qualified until two accounts can authenticate,
restart, refresh, and reconnect without sharing the vendor CLI's global
profile.

Authentication success is persisted before the first usage validation. A
failed initial usage fetch leaves a visible account in a `needs attention`
state with diagnostics. It does not discard a successful login and force the
user to authenticate again.

This changes the validation behavior described in
`2026-07-30-account-management-design.md`: connection is no longer
all-or-nothing when authentication succeeded but usage validation failed.

## Normalized Usage Model

Adapters return a collection of normalized `UsageLimit` values. A limit is
either timed or a balance.

A timed limit contains:

- a stable provider-local pool ID;
- an optional pool or model label;
- normalized remaining fraction;
- window start when known;
- reset time;
- comparison group;
- provider-reported scope metadata needed for display.

A balance contains:

- a stable provider-local pool ID;
- a display label;
- remaining amount;
- unit, such as AI credits or USD;
- optional billing-cycle end.

The comparison group is semantic rather than inferred from label text:

- five hours;
- day;
- week;
- month;
- custom duration.

Adapters explicitly map provider fields to these groups. They also explicitly
normalize whether the provider reports used or remaining capacity. The shared
model clamps display fractions to the valid range but does not merge
independent pools, estimate missing limits, or invent reset dates.

If a provider reports multiple independent model pools, they remain separate
limits attached to the same account and sort together.

## Timeline and Balance Rendering

The approved aligned Gantt visualization remains the primary timed-limit
presentation.

Sections render in this order when present:

1. shared five-hour timeline;
2. shared weekly timeline;
3. additional timed groups, ordered from shorter to longer;
4. compact balances.

Only limits with comparable semantics share an axis. Balances never render on
a Gantt axis. Empty sections remain absent.

Within a section, rows preserve provider catalog order and the user's account
order. Multiple pools for one account are adjacent subrows with a secondary
pool or model label. Usage values never reorder accounts.

The provider/account identity, percentage remaining, Gantt bar, and reset
interval continue to follow the approved aligned-row design. The view sizes to
its content and uses scrolling only when the complete content cannot fit on
the active screen.

## Account Dashboards

Clicking an account row opens a dedicated account-dashboard window.

The dashboard action applies to the row's noninteractive surface. Clicking the
account name still begins inline rename, and the drag handle, Reconnect button,
and overflow-menu actions retain their existing behavior.

Generalize the existing Claude WebKit profile store into an account-scoped
profile store backed by `WKWebsiteDataStore(forIdentifier:)`. Each account
dashboard uses its own persistent profile so cookies and caches cannot overwrite
another account.

Each provider declares one dashboard strategy:

- `embedded`, with a provider dashboard URL and account WebKit profile;
- `nativeDetail`, rendered from normalized usage and diagnostics;
- `external`, opening the provider dashboard in the system browser;
- a native detail view with an external provider-dashboard action.

Usage authentication and dashboard authentication remain separate. An API key
or OAuth access token does not imply that WebKit has browser cookies.

When the provider permits embedded login, the first dashboard open can ask the
user to sign in inside that account's isolated WebKit profile. When the
provider blocks embedded authentication, the app shows the native detail view
and opens the real dashboard in the system browser.

Google explicitly rejects OAuth authorization in `WKWebView`. Antigravity
therefore uses native detail plus system-browser fallback unless Google
introduces a supported session-sharing mechanism. The app must not copy,
inject, or synthesize browser cookies to bypass this boundary.

Removing an account deletes both its Keychain record and its account WebKit
data store after all WebKit references have been released.

References:

- [Apple `WKWebsiteDataStore`](https://developer.apple.com/documentation/webkit/wkwebsitedatastore)
- [Google OAuth for native apps](https://developers.google.com/identity/protocols/oauth2/native-app)
- [RFC 8252: OAuth 2.0 for Native Apps](https://datatracker.ietf.org/doc/rfc8252/)

## Refresh Coordinator

A single refresh coordinator owns all automatic and manual refresh scheduling.
Provider screens and adapters do not create their own timers.

The coordinator:

- renders cached snapshots immediately at launch;
- checks account eligibility on a lightweight timer;
- checks again after macOS wakes from sleep;
- serializes refreshes for the same account;
- limits concurrent refreshes across accounts;
- injects its clock and scheduling dependencies for deterministic tests.

Provider contact for a usage refresh is allowed only when at least ten minutes
have elapsed since that account's previous attempt. Manual refresh requests are
coalesced and respect the same floor. Login, explicit reconnect, and the first
validation for a never-attempted account are exempt because they are
user-initiated connection work.

Local Keychain reads do not count as provider contact. When token refresh is
required, it happens inside the same gated account refresh cycle rather than
on a second timer.

The coordinator tracks attempt time separately from last-success time. A
transient failed request therefore cannot cause a retry loop while the UI can
still report the age of the last good data.

## Refresh and Error States

The shared state model distinguishes:

- never attempted;
- fresh;
- stale with last-good data;
- authentication required;
- rate limited until a known date;
- unsupported or unqualified response.

Transient network, server, decoding, and CLI failures retain the last-good
snapshot. Authentication failures stop automatic requests for that account
until reconnect. A provider rate limit suppresses attempts until its reported
retry or reset time, subject to the ten-minute floor.

Manual refresh indicates why an account is not yet eligible and when it can be
contacted again.

## Diagnostics and Redaction

Diagnostics are account-scoped and copyable. They include:

- provider and non-secret local account ID;
- adapter and application version;
- attempt and success timestamps;
- normalized state transition;
- HTTP host/path, status, and provider request ID; or
- CLI executable path, version, exit status, and sanitized failure category.

Diagnostics never include:

- access or refresh tokens;
- API keys;
- cookies;
- authorization headers;
- raw Keychain payloads;
- unredacted provider response bodies;
- unredacted CLI output.

Adapters convert provider responses and CLI failures into structured diagnostic
fields at their boundary. The shared application does not apply a best-effort
regex over arbitrary secret-bearing output.

## Initial Provider Capability Matrix

| Product | Distinct pool | Candidate connection | Reported limits | Dashboard |
| --- | --- | --- | --- | --- |
| GitHub Copilot | Personal or organization/enterprise billing scope | GitHub device OAuth | Independent limited Copilot quota snapshots | Native plus external |
| SuperGrok | SuperGrok subscription | Account-scoped Grok CLI device OAuth | Shared weekly percentage, reset, product balances, extra credits | Isolated embedded login |
| Antigravity | Google AI plan's Antigravity allowance | Blocked: AGY uses the shared macOS Keychain | Authoritative CLI usage exists, but accounts cannot be isolated | Hidden |
| Factory | Factory organization plan | Per-account Factory API key | Independent Standard and Droid Core five-hour, weekly, and monthly pools; extra-usage balance | Native plus external |
| OpenCode Go | Go subscription | Isolated workspace WebKit session | Provider-present five-hour, weekly, and monthly windows | Isolated embedded workspace |
| OpenCode Zen | Zen workspace | Isolated workspace WebKit session | Dollar balance and provider-configured cycle limit | Isolated embedded workspace |
| MiniMax Token Plan | Token Plan API key | API key | Five-hour and weekly text limits; separate modality limits where authoritative | Embedded candidate or native plus external |

Official product surfaces:

- [GitHub billing usage API](https://docs.github.com/en/rest/billing/usage)
- [SuperGrok usage and limits](https://docs.x.ai/grok/faq)
- [Antigravity plans](https://antigravity.google/docs/plans)
- [Antigravity `/usage`](https://antigravity.google/docs/cli/commands/usage)
- [Antigravity `/credits`](https://antigravity.google/docs/cli-credits)
- [Factory plans and `/limits`](https://docs.factory.ai/pricing)
- [OpenCode Go](https://opencode.ai/docs/go)
- [OpenCode Zen](https://opencode.ai/docs/zen)
- [MiniMax Token Plan](https://platform.minimax.io/docs/token-plan/intro)
- [MiniMax CLI quota command](https://platform.minimax.io/docs/token-plan/minimax-cli)

## Qualification and Release Order

Implement and qualify providers in this order:

1. MiniMax;
2. GitHub Copilot;
3. Antigravity;
4. Factory;
5. OpenCode Go and OpenCode Zen;
6. SuperGrok.

This order prioritizes documented machine-readable interfaces before
interactive CLI and web-session probes. It does not imply that experimental
adapters are visible in release builds.

Every newly added provider must pass:

- two distinct accounts connected without credential sharing;
- signed-app restart with both accounts retained;
- authoritative retrieval of every offered quota window;
- normalization of used-versus-remaining semantics;
- ten-minute floor and wake-from-sleep refresh;
- token expiry or session expiry;
- reconnect without losing cached last-good usage;
- dashboard profile isolation or documented external fallback;
- deletion of one account without affecting another;
- menu-bar, Settings, and floating-widget acceptance in the signed app.

Automated evidence includes:

- sanitized provider response fixtures;
- structured decoder and normalization tests;
- connection identity and duplicate-scope tests;
- fake HTTP service or fake executable adapter tests;
- deterministic refresh-coordinator clock tests;
- cache and persistence tests;
- WebKit data-store isolation and removal tests.

Tests exercise adapter inputs, outputs, and state transitions. They do not
assert large rendered commands, scripts, HTML, JSON, or diagnostic strings.

## Existing Account Compatibility Boundary

Claude, Codex, and Kimi retain their current stable serialized provider values,
Keychain service/account addressing, and cached snapshot locations. The
provider-catalog refactor should consume those records without adding a legacy
format or broad migration.

If implementation inspection shows that preserving existing accounts requires
compatibility decoding or storage migration, stop and get Jesse's explicit
approval before adding it.

## Completion Criteria

The provider-framework milestone is complete when:

- existing Claude, Codex, and Kimi behavior uses the catalog without
  regression;
- the shared account, refresh, dashboard, and diagnostic boundaries no longer
  contain provider-specific switches;
- MiniMax and GitHub Copilot are qualified end to end;
- later adapters can be implemented without changing the normalized usage,
  refresh, Settings, dashboard-window, or timeline architecture;
- the repository qualification matrix accurately distinguishes researched,
  experimental, and qualified providers.

The provider-expansion project is complete only when GitHub Copilot, SuperGrok,
Antigravity, Factory, OpenCode Go, OpenCode Zen, and MiniMax are qualified and
release-visible. If a provider proves technically unavailable, its deferral
requires a documented qualification result and Jesse's approval.

Adding all researched providers is a sequence of qualification tasks, not a
single completion claim after the catalog lands.
