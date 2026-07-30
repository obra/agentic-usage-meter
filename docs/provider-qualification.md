# Provider qualification

Provider adapters are qualified separately from fixture-based automated tests.
The probe prints only normalized window data and never prints credentials,
request headers, raw provider responses, or account identity unless an adapter
explicitly obtains a safe display identity.

## Claude

Automated fixture and request-contract coverage is implemented. Live
qualification is pending a token created with `claude setup-token`.

## Codex

Not yet qualified.

## Kimi

Not yet qualified.
