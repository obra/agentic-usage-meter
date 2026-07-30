# Provider qualification

Provider adapters are qualified separately from fixture-based automated tests.
The probe prints only normalized window data and never prints credentials,
request headers, raw provider responses, or account identity unless an adapter
explicitly obtains a safe display identity.

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

Not yet qualified.

## Kimi

Not yet qualified.
