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
| MiniMax Token Plan | API key and documented remains endpoint | Automated adapter complete | Experimental builds |
| GitHub Copilot | GitHub OAuth and billing usage API | Researched | Hidden |
| Antigravity | Isolated CLI profile and `/usage` | Researched | Hidden |
| Factory | Isolated Droid profile and `/limits` | Researched | Hidden |
| OpenCode Go | API key plus console/endpoint qualification | Researched | Hidden |
| OpenCode Zen | API key plus console/endpoint qualification | Researched | Hidden |
| SuperGrok | Isolated web session and Usage dashboard | Researched | Hidden |

`Researched` means an authoritative usage surface has been identified but no
real multi-account adapter has passed the qualification gate. Development code
may mark an in-progress adapter experimental; release builds keep it hidden.

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
- The provider is visible only in development builds pending a real
  two-account qualification and cleanup check.
