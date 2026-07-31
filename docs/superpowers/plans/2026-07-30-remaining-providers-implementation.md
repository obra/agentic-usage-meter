# Remaining Provider Expansion Implementation Plan

**Date:** 2026-07-30

**Status:** In progress

**Design:** `docs/superpowers/specs/2026-07-30-provider-expansion-design.md`

## Guardrails

- Keep every new provider `experimental` until two real accounts qualify.
- Store one typed credential or isolated profile reference per local account.
- Never synthesize a quota window from local activity or an assumed plan.
- Preserve independent provider pools instead of summing unlike allowances.
- Route every refresh through the existing ten-minute floor.
- Test decoders with complete sanitized provider responses and adapters with
  external transport or process boundaries replaced by narrow fakes.

## Task 1: GitHub Copilot

1. Add failing request tests for GitHub's device authorization and access-token
   polling contracts.
2. Implement the device OAuth request builder and flow.
3. Add a failing decoder test for independent Copilot quota snapshots, unlimited
   pool omission, identity, and reset time.
4. Implement the Copilot credential, decoder, and account adapter against
   `GET /copilot_internal/user`.
5. Add failing UI model tests for multi-account save, reconnect, and duplicate
   provider identity handling.
6. Implement the Copilot connection view, catalog definition, and live adapter
   registration.
7. Run focused tests, then the full suite, and commit.

## Task 2: SuperGrok

1. Add failing tests for an account-scoped Grok CLI profile and sanitized auth
   document loading.
2. Add a failing decoder test for the current weekly usage pool, reset, product
   breakdown balances, and extra-credit balance.
3. Implement the isolated profile credential, billing request, decoder, and
   adapter.
4. Implement a connection flow that runs Grok device authentication against the
   account profile without reading the user's default Grok profile.
5. Wire the signed-in embedded usage dashboard to the same account profile.
6. Run focused tests, then the full suite, and commit.

## Task 3: OpenCode Go and Zen

1. Add failing tests for isolated WebKit profile ownership and workspace
   discovery from OpenCode dashboard navigation.
2. Add failing HTML/JSON fixture tests for Go rolling, weekly, and monthly
   windows.
3. Add failing fixture tests for Zen balance and any provider-reported cycle
   limit; omit values not present in the provider response.
4. Implement profile-backed dashboard clients, decoders, and adapters.
5. Implement connection views that authenticate the isolated dashboard and
   persist only profile/workspace references.
6. Run focused tests, then the full suite, and commit.

## Task 4: Antigravity and Factory

The installed CLIs changed the viable architecture. Jesse approved using
Factory's supported per-account API keys and keeping Antigravity unavailable
until Google provides account-scoped credential isolation.

1. Add failing decoder tests using a sanitized Factory billing-limits response.
2. Implement a typed Factory API-key credential and direct adapter for values
   explicitly reported by `GET /api/billing/limits`.
3. Preserve Standard and Droid Core pools independently, omit missing windows,
   and expose the optional extra-usage balance.
4. Add failing catalog and connection-copy tests, then wire Factory into the
   development-only provider picker, account lifecycle, and native detail view.
5. Record that isolated `$HOME` directories do not isolate Antigravity's
   shared macOS Keychain authentication, and keep the provider unavailable.
6. Run focused tests, then the full suite, and commit.

## Task 5: Product Verification

1. Run `swift test`.
2. Run `swift build -c release`.
3. Assemble the application bundle.
4. Ad-hoc sign and run strict code-signature verification.
5. Exercise Add Account, independent reconnect, refresh, deletion, ordering,
   dashboard isolation, and ten-minute refresh behavior for every provider that
   can be authenticated locally.
6. Keep any provider without real two-account qualification hidden from release
   builds and document the exact remaining qualification boundary.
