# Provider qualification

Provider adapters are qualified separately from fixture-based automated tests.
The probe prints only normalized window data and never prints credentials,
request headers, raw provider responses, or account identity unless an adapter
explicitly obtains a safe display identity.

## Qualification matrix

| Product | Integration surface | Status | Release visibility |
| --- | --- | --- | --- |
| Claude | Isolated WebKit session | Qualified with two profiles | Enabled |
| Codex | Browser OAuth and usage API | Qualified with two accounts | Enabled |
| Kimi | Device OAuth and usage API | Qualified current flow; second-account gate outstanding | Enabled (existing) |
| MiniMax Token Plan | API key and documented remains endpoint | Automated adapter complete | Selectable, experimental |
| GitHub Copilot | GitHub device OAuth and quota API | Automated adapter complete | Selectable, experimental |
| Antigravity | AGY CLI with shared macOS Keychain auth | Multi-account isolation blocked | Hidden |
| Factory | Per-account API key and billing-limits API | Automated adapter complete | Selectable, experimental |
| OpenCode Go | Isolated web session and workspace dashboard | Automated adapter complete | Selectable, experimental |
| OpenCode Zen | Isolated web session and workspace billing | Automated adapter complete | Selectable, experimental |
| SuperGrok | Account-scoped device OAuth and Usage dashboard | Automated adapter complete | Selectable, experimental |

`Automated adapter complete` means fixture, request, error, persistence, and
cleanup contracts pass, but no real two-account qualification has completed.
Release and development builds expose automated adapters while preserving
their experimental qualification state. Unavailable providers remain hidden.

The provider expansion architecture and common release gate are specified in
`docs/superpowers/specs/2026-07-30-provider-expansion-design.md`.

## Claude

Automated fixture and request-contract coverage is implemented for the original
OAuth usage hypothesis. A live token created by Claude Code 2.1.220 with
`claude setup-token` was rejected by that probe. Anthropic documents setup
tokens as inference-only, while the usage feature requires profile scope.

Anthropic's current Agent SDK and legal documentation says third-party
developers require prior approval to offer Claude.ai login or Claude.ai rate
limits. The project owner has chosen to proceed with a local embedded-login
qualification. That gate will use separate identified WebKit data stores and
will not record credentials or account identity.

### 2026-07-29 isolated web-session qualification

The probe was run on macOS 26.5.2 using login behavior adapted from Claude
Usage Tracker commit `574eb3720c9b793ed9d1477861187f7c9c23b6e2`.

- Profile A authenticated, returned two organizations, and the selected
  organization returned one 18,000-second window and one 604,800-second
  window.
- Profile B authenticated and returned two organizations with identical
  display names. The probe presented both names without another
  discriminator. Selecting the second organization caused the usage endpoint
  to return an authentication/authorization failure.
- After changing the probe to the tracker's first-organization rule, profile B
  reused its existing session without another sign-in. It returned one
  18,000-second window and one 604,800-second window.
- Profile A then reused its original session without another sign-in and
  returned its original, distinct usage values. Authenticating profile B did
  not overwrite profile A.
- Both temporary profile stores were removed after the persistence check, and
  a WebKit identifier query confirmed that neither remained.

This was a probe selection failure, not evidence that the second WebKit session
failed. The researched tracker auto-selects the first organization when no
organization has been stored. The probe must stop asking the user to guess
between duplicate names, so the qualified implementation now selects the
tracker-compatible first organization. The transient blank login window was
also traced to displaying the raw web view before its first navigation
finished; the probe now keeps a loading presentation visible until that
callback.

## Codex

The implementation follows OpenAI Codex commit
`406dc9239492aff6d295cca5eebe2a548548d42f`: browser OAuth with PKCE, the
registered `http://localhost:<port>/auth/callback` redirect, token refresh, and
the ChatGPT usage endpoint. The local listener binds only to loopback. Tokens
are stored per app account in Keychain and are never written to the shared
Codex CLI configuration.

### 2026-07-29 two-account OAuth qualification

The probe was run on macOS 26.5.2 with two separate ChatGPT subscriptions.

- The system browser was activated for each authorization and the request
  explicitly asked the authorization server to select an account.
- Using `127.0.0.1` in the redirect URI caused the authorization server to
  reject the request even though it reaches the same loopback interface.
  Restoring the registered `localhost` spelling fixed the request. The
  listener continues to bind to `127.0.0.1`.
- A repeated authorization initially returned the already-saved identity. The
  probe's identity gate detected that it was not a distinct account and did
  not save it as the second subscription.
- A subsequent authorization returned a distinct personal identity. Both
  account credentials then existed in separate Keychain records.
- After waiting at least ten minutes from the initial usage request for each
  account, both credentials were loaded from Keychain, refreshed independently,
  and used for one usage request each.
- The two live responses contained distinct weekly windows. Neither response
  included a five-hour window, and the decoder preserved the available weekly
  value rather than inventing the missing window.
- Both temporary Keychain records were removed after the refresh and
  persistence check, and lookup confirmed that neither remained.

## Kimi

The automated adapter contract follows MoonshotAI Kimi CLI commit
`4a550effdfcb29a25a5d325bf935296cc50cd417`.

- Authentication uses Kimi's device authorization endpoint and opens the
  supplied `auth.kimi.com` verification URL in the regular system browser.
- Credentials are polled and refreshed with the device headers used by the
  current Kimi CLI.
- Usage is fetched from `https://api.kimi.com/coding/v1/usages`.
- The decoder supports the current CLI parser's weekly summary and limit array,
  including a 300-minute rolling window, nested or item-level details,
  remaining quota, reset aliases, and nanosecond ISO timestamps.

### 2026-07-29 device-OAuth qualification

The probe was run on macOS 26.5.2 with one Kimi Code subscription.

- The device-authorization API returned an HTTPS verification URL on
  `www.kimi.com`, not `auth.kimi.com`. The original host allowlist rejected
  that valid response before opening the browser. The qualified flow now
  accepts the two official Kimi hosts and continues to reject arbitrary hosts.
- Authorization completed in the regular system browser, and the credential
  was stored in an isolated Keychain record rather than the existing Kimi CLI
  login.
- The initial live usage response contained one 604,800-second weekly window.
  It did not contain an 18,000-second rolling window.
- After waiting at least ten minutes, the credential was loaded from Keychain,
  refreshed with token rotation, and used for one more usage request. The
  response again contained the weekly window only.
- The temporary Keychain record was removed after the refresh and persistence
  check, and lookup confirmed that it no longer existed.

The adapter remains capable of decoding Kimi's documented 300-minute limit
when the provider supplies it. The UI must preserve the live weekly-only state
without inventing a five-hour value.

## MiniMax Token Plan

The automated adapter behavior is adapted from OpenCode Bar commit
`4c501b3d97f2f88ff5178ec20d4e45fe3108b3fe`.

- Authentication uses an account-scoped API key stored in the macOS Keychain.
- Usage is fetched from
  `https://api.minimax.io/v1/api/openplatform/coding_plan/remains`.
- `current_interval_usage_count` and `current_weekly_usage_count` are treated
  as remaining counts despite their names.
- Zero-capacity modalities are ignored, and numeric strings are accepted
  without rounding the normalized fraction to an integer percentage.
- The provider is selectable but remains experimental pending a real
  two-account qualification and cleanup check.

### 2026-07-30 mechanical qualification

- The sanitized probe accepts account-scoped `login`, `usage`, and `delete`
  commands. Secret entry disables terminal echo, and output contains the local
  account UUID plus normalized windows without credentials, headers, raw
  responses, or identity.
- The 184-test Swift package suite, production build, app assembly, ad-hoc
  signing, and strict code-signature verification passed.
- The distribution verifier rejected the ad-hoc artifact at Gatekeeper. That
  is expected because the local artifact has no Developer ID signature,
  notarization ticket, or staple; it is not distribution evidence.
- Real two-account validation, ten-minute persistence refresh, console
  comparison, and independent deletion remain outstanding. MiniMax therefore
  remains experimental.

## GitHub Copilot

The automated quota interpretation is adapted from OpenCode Bar commit
`4c501b3d97f2f88ff5178ec20d4e45fe3108b3fe`.

- Authentication uses GitHub's device authorization flow in the regular
  browser. The approved GitHub user ID and login are stored with the token in
  an account-scoped macOS Keychain record.
- Usage is fetched from
  `https://api.github.com/copilot_internal/user`.
- Limited `quota_snapshots` remain independent monthly rows. Unlimited pools
  and negative sentinel entitlements are omitted rather than converted into
  synthetic capacity.
- A usage response reporting a different GitHub user ID is rejected, so one
  account's quota cannot be displayed under another account's row.
- The provider is selectable but remains experimental pending real
  qualification.

### 2026-07-30 mechanical qualification

- A credential-free request to GitHub's device-code endpoint confirmed that
  the Copilot CLI OAuth client identifier is currently accepted and returns
  GitHub's HTTPS device authorization route.
- The 194-test package suite passed after the OAuth flow, account adapter,
  decoder, duplicate-identity gate, connection UI, and independent cleanup
  behavior were added.
- Real two-account authorization, ten-minute persistence refresh, comparison
  with GitHub's billing UI, and independent deletion remain outstanding.
  GitHub Copilot therefore remains experimental.

## Factory

The installed Droid CLI 0.120.1 fetches its current token-rate limits from
`https://api.factory.ai/api/billing/limits`. Factory's API documentation
specifies Bearer authentication for Factory API keys, and the application
stores one API key per local account in the macOS Keychain.

- Standard and Droid Core 5-hour, 7-day, and rolling 30-day pools remain
  independent.
- A missing pool or window is omitted rather than inferred.
- `usedPercent` is normalized without integer rounding, and `windowEnd` is
  preserved as the provider reset time.
- `extraUsageBalanceCents` is presented as an optional USD balance only when
  the provider supplies it.
- The provider is selectable but remains experimental pending real two-account
  qualification, ten-minute persistence refresh, dashboard comparison, and
  independent deletion.

### 2026-07-30 mechanical qualification

- A credential-free request reached the current billing-limits route and
  returned HTTP 401 with `x-matched-path: /api/billing/limits`, confirming the
  live route without transmitting a key.
- The complete Swift package suite passed 241 tests in 39 suites.
- The release product compiled, assembled, and passed strict Developer ID
  signature verification with the hardened runtime and Apple timestamp.
- Gatekeeper correctly rejected the local artifact as `Unnotarized Developer
  ID`; notarization and stapling remain separate distribution gates.

### 2026-07-31 inactive-window qualification

- A live zero-usage response retained all Standard and Droid Core pool objects
  but omitted `windowEnd` from every rolling window. Factory documents that a
  rolling window starts when Droid is first used, so no reset exists yet for
  those inactive windows.
- The decoder omits a zero-percent window without an end date instead of
  rejecting the whole account. A nonzero window without an end date remains an
  unsupported response because the application must not invent a reset.

## Antigravity

Antigravity CLI 1.0.2 stores its Google authentication in the macOS Keychain.
Changing `$HOME` isolates settings and cache files but does not isolate those
credentials, and no documented account/profile selector was found. The app
therefore keeps Antigravity unavailable instead of presenting a false
multi-account connection flow. Qualification can resume when Google exposes
account-scoped credentials or a supported profile selector.
