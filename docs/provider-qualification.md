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

## Codex

Not yet qualified.

## Kimi

Not yet qualified.
