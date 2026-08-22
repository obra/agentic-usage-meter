# Agentic Usage Meter — Desktop (cross-platform port)

A system-tray app that shows token/quota usage across multiple coding-agent
subscriptions. Cross-platform (Windows, macOS, Linux) Electron + TypeScript
port of the macOS app
[`prime-radiant-inc/agentic-usage-meter`](https://github.com/prime-radiant-inc/agentic-usage-meter).

Supported providers: Claude (API + web), Codex (ChatGPT OAuth), Kimi,
GitHub Copilot, MiniMax, Factory, z.ai, MiMo, OpenCode (Go + Zen), SuperGrok.

## Prerequisites

- Node.js 20+ and npm
- On Windows: nothing else (prebuilt Electron binaries are used)

## Setup

```sh
npm install
# If Electron's binary download was blocked (install scripts gated):
node node_modules/electron/install.js
```

## Run

```sh
npm start            # build + launch the tray app
npm run sample       # launch with sample data (no credentials needed)
npm run smoke        # launch, open panel, exit 0 (CI smoke check)
```

## Test

```sh
npm test             # vitest unit tests (decoder fixtures from the macOS repo)
npm run typecheck    # main + renderer + tests
```

## Build distributables

```sh
npm run dist:win     # Windows: NSIS installer + portable zip (in release/)
npm run dist:mac     # macOS: dmg + zip
npm run dist:linux   # Linux: AppImage + deb
```

Windows packages can be built from macOS/Linux hosts (electron-builder
cross-builds NSIS). Code signing is not configured; Windows SmartScreen will
warn on first launch of unsigned builds.

## Layout

- `src/core/` — provider clients, decoders, credential store contract,
  refresh engine (no Electron imports; shared with tests)
- `src/main/` — Electron main process: tray, windows, IPC, safeStorage
  credential store, OAuth/device-flow connect orchestration
- `src/preload/` — context-bridge preloads (compiled to `.cjs`)
- `src/renderer/` — panel, floating widget, settings UIs
- `tests/` — vitest suite; `tests/fixtures/` holds response fixtures ported
  from the macOS repo's `Tests/*/Fixtures/`
- `repo/` — read-only reference clone of the original macOS source
