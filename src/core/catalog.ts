// Provider catalog — port of repo/Sources/UsageMeterCore/Providers/
// ProviderCatalog.swift. Colors are the Swift RGB values rendered as hex.

import type { Provider } from "./models.js";

export type ProviderReleaseState = "qualified" | "experimental" | "unavailable";

export type ProviderConnectionStrategy =
  | { type: "isolatedWebSession" }
  | { type: "browserOAuth" }
  | { type: "deviceOAuth" }
  | { type: "apiKey" }
  | { type: "isolatedCLIProfile"; executable: string };

export interface ProviderDefinition {
  provider: Provider;
  displayName: string;
  connectionDetail: string;
  color: string; // hex
  releaseState: ProviderReleaseState;
  connectionStrategy: ProviderConnectionStrategy;
  dashboardURL: string | null;
}

function hex(red: number, green: number, blue: number): string {
  const channel = (value: number) =>
    Math.round(Math.min(Math.max(value, 0), 1) * 255)
      .toString(16)
      .padStart(2, "0");
  return `#${channel(red)}${channel(green)}${channel(blue)}`;
}

export const providerCatalog: ProviderDefinition[] = [
  {
    provider: "claude",
    displayName: "Claude",
    connectionDetail: "Isolated browser session",
    color: hex(0.86, 0.36, 0.18),
    releaseState: "qualified",
    connectionStrategy: { type: "isolatedWebSession" },
    dashboardURL: "https://claude.ai/settings/usage",
  },
  {
    provider: "codex",
    displayName: "Codex",
    connectionDetail: "ChatGPT OAuth in your browser",
    color: hex(0.15, 0.68, 0.55),
    releaseState: "qualified",
    connectionStrategy: { type: "browserOAuth" },
    dashboardURL: "https://chatgpt.com/codex/settings/usage",
  },
  {
    provider: "kimi",
    displayName: "Kimi",
    connectionDetail: "Device authorization",
    color: hex(0.33, 0.45, 0.92),
    releaseState: "qualified",
    connectionStrategy: { type: "deviceOAuth" },
    dashboardURL: "https://www.kimi.com/code/console",
  },
  {
    provider: "minimax",
    displayName: "MiniMax",
    connectionDetail: "Token Plan API key",
    color: hex(0.91, 0.28, 0.38),
    releaseState: "experimental",
    connectionStrategy: { type: "apiKey" },
    dashboardURL: "https://www.minimax.io/platform",
  },
  {
    provider: "github-copilot",
    displayName: "GitHub",
    connectionDetail: "GitHub device OAuth",
    color: hex(0.5, 0.36, 0.88),
    releaseState: "experimental",
    connectionStrategy: { type: "deviceOAuth" },
    dashboardURL: "https://github.com/settings/billing/summary",
  },
  {
    provider: "antigravity",
    displayName: "Antigravity",
    connectionDetail: "Not available: no isolated per-account credential store",
    color: hex(0.25, 0.55, 0.95),
    releaseState: "unavailable",
    connectionStrategy: { type: "isolatedCLIProfile", executable: "agy" },
    dashboardURL: "https://antigravity.google/",
  },
  {
    provider: "factory",
    displayName: "Factory",
    connectionDetail: "Per-account Factory API key",
    color: hex(0.89, 0.55, 0.18),
    releaseState: "experimental",
    connectionStrategy: { type: "apiKey" },
    dashboardURL: "https://app.factory.ai/settings/usage",
  },
  {
    provider: "opencode-go",
    displayName: "OpenCode Go",
    connectionDetail: "Isolated OpenCode session",
    color: hex(0.18, 0.7, 0.72),
    releaseState: "experimental",
    connectionStrategy: { type: "isolatedWebSession" },
    dashboardURL: "https://opencode.ai/go",
  },
  {
    provider: "opencode-zen",
    displayName: "OpenCode Zen",
    connectionDetail: "Isolated OpenCode session",
    color: hex(0.51, 0.61, 0.29),
    releaseState: "experimental",
    connectionStrategy: { type: "isolatedWebSession" },
    dashboardURL: "https://opencode.ai/zen",
  },
  {
    provider: "supergrok",
    displayName: "SuperGrok",
    connectionDetail: "Grok device OAuth (requires the grok CLI)",
    color: hex(0.36, 0.36, 0.38),
    releaseState: "experimental",
    connectionStrategy: { type: "isolatedCLIProfile", executable: "grok" },
    dashboardURL: "https://grok.com/?_s=usage",
  },
  {
    provider: "zai",
    displayName: "Z.ai",
    connectionDetail: "Coding Plan API key",
    color: hex(0.2, 0.42, 0.95),
    releaseState: "experimental",
    connectionStrategy: { type: "apiKey" },
    dashboardURL: "https://z.ai/manage-apikey/coding-plan/personal/usage",
  },
  {
    provider: "mimo",
    displayName: "MiMo",
    connectionDetail: "Isolated browser session",
    color: hex(1.0, 0.44, 0.2),
    releaseState: "experimental",
    connectionStrategy: { type: "isolatedWebSession" },
    dashboardURL: "https://platform.xiaomimimo.com/console/balance",
  },
];

export function providerDefinition(provider: Provider): ProviderDefinition {
  const definition = providerCatalog.find((entry) => entry.provider === provider);
  if (!definition) throw new Error(`Unknown provider: ${provider}`);
  return definition;
}

export function connectableProviders(): ProviderDefinition[] {
  return providerCatalog.filter((entry) => entry.releaseState !== "unavailable");
}

export function providerSortIndex(provider: Provider): number {
  const index = providerCatalog.findIndex((entry) => entry.provider === provider);
  return index === -1 ? Number.MAX_SAFE_INTEGER : index;
}
