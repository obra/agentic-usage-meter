// Domain models — a faithful TypeScript port of
// repo/Sources/UsageMeterCore/Domain/UsageModels.swift.
//
// Dates cross process and storage boundaries as ISO-8601 strings; the
// `Stored*` shapes at the bottom define the persisted JSON contract.

export const Providers = [
  "claude",
  "codex",
  "kimi",
  "minimax",
  "github-copilot",
  "antigravity",
  "factory",
  "opencode-go",
  "opencode-zen",
  "supergrok",
  "zai",
  "mimo",
] as const;

export type Provider = (typeof Providers)[number];

export function isProvider(value: string): value is Provider {
  return (Providers as readonly string[]).includes(value);
}

export interface SubscriptionAccount {
  id: string; // UUID
  provider: Provider;
  displayName: string;
  authenticatedIdentity?: string;
  displayOrder: number;
  claudeOrganizationID?: string;
  // For web-session providers the Electron session partition holding the
  // account's isolated cookies ("" means "not used").
  sessionPartition?: string;
}

export type UsageWindowKind = "short" | "daily" | "weekly" | "monthly" | "custom";

export interface UsageWindow {
  id: string;
  kind: UsageWindowKind;
  duration: number; // seconds
  resetAt: string | null; // ISO date
  consumedFraction: number; // 0...1
  label: string | null;
  reportedStartAt: string | null; // ISO date
}

// Ports the UsageWindow failable initializer's invariants.
export function makeUsageWindow(input: {
  id: string;
  kind: UsageWindowKind;
  duration: number;
  resetAt: Date | null;
  consumedFraction: number;
  label?: string | null;
  reportedStartAt?: Date | null;
}): UsageWindow | null {
  const { id, kind, duration, resetAt, consumedFraction } = input;
  const label = input.label ?? null;
  const reportedStartAt = input.reportedStartAt ?? null;
  if (
    id.length === 0 ||
    !Number.isFinite(duration) ||
    duration <= 0 ||
    !Number.isFinite(consumedFraction) ||
    consumedFraction < 0 ||
    consumedFraction > 1
  ) {
    return null;
  }
  if (resetAt === null && !(consumedFraction === 0 && reportedStartAt === null)) {
    return null;
  }
  return {
    id,
    kind,
    duration,
    resetAt: resetAt ? resetAt.toISOString() : null,
    consumedFraction,
    label,
    reportedStartAt: reportedStartAt ? reportedStartAt.toISOString() : null,
  };
}

export function windowStartAt(window: UsageWindow): Date | null {
  if (window.reportedStartAt) return new Date(window.reportedStartAt);
  if (window.resetAt) {
    return new Date(new Date(window.resetAt).getTime() - window.duration * 1000);
  }
  return null;
}

export function windowRemainingFraction(window: UsageWindow): number {
  return 1 - window.consumedFraction;
}

export type UsageBalanceValue =
  | { state: "available"; amount: number; unit: string }
  | { state: "unlimited" }
  | { state: "disabled" };

export interface UsageBalance {
  id: string;
  label: string;
  value: UsageBalanceValue;
  cycleEndsAt: string | null;
}

export function makeUsageBalance(input: {
  id: string;
  label: string;
  value: UsageBalanceValue;
  cycleEndsAt?: Date | null;
}): UsageBalance | null {
  const id = input.id.trim();
  const label = input.label.trim();
  if (!id || !label) return null;
  const value = input.value;
  if (value.state === "available") {
    const unit = value.unit.trim();
    if (!Number.isFinite(value.amount) || Number.isNaN(value.amount) || !unit) {
      return null;
    }
    return {
      id,
      label,
      value: { state: "available", amount: value.amount, unit },
      cycleEndsAt: input.cycleEndsAt ? input.cycleEndsAt.toISOString() : null,
    };
  }
  return {
    id,
    label,
    value,
    cycleEndsAt: input.cycleEndsAt ? input.cycleEndsAt.toISOString() : null,
  };
}

export function makeAvailableBalance(input: {
  id: string;
  label: string;
  remainingAmount: number;
  unit: string;
  cycleEndsAt?: Date | null;
}): UsageBalance | null {
  if (!Number.isFinite(input.remainingAmount)) return null;
  return makeUsageBalance({
    id: input.id,
    label: input.label,
    value: { state: "available", amount: input.remainingAmount, unit: input.unit },
    cycleEndsAt: input.cycleEndsAt ?? null,
  });
}

export interface UsageSnapshot {
  accountID: string;
  fetchedAt: string; // ISO date
  windows: UsageWindow[];
  balances: UsageBalance[];
}

// ---------------------------------------------------------------------------
// Credentials
// ---------------------------------------------------------------------------

export interface OAuthCredential {
  accessToken: string;
  refreshToken?: string;
  idToken?: string;
  accountID?: string;
  expiresAt?: string; // ISO date
}

// The credential payload is provider-specific and stored encrypted per
// account; the `kind` tag mirrors the macOS ProviderCredential enum plus the
// per-provider structs used by the experimental providers.
export type AccountCredential =
  | { kind: "claude-token"; token: string }
  | { kind: "claude-web" } // cookies live in the account's session partition
  | { kind: "codex"; oauth: OAuthCredential }
  | { kind: "kimi"; oauth: OAuthCredential }
  | { kind: "github-copilot"; accessToken: string; userID: string; login: string }
  | { kind: "api-key"; apiKey: string }
  | { kind: "mimo-web"; cookieHeader: string }
  | { kind: "opencode"; workspaceID: string; authCookie: string }
  | {
      kind: "supergrok";
      accessToken: string;
      email?: string;
      teamID?: string;
      userID?: string;
      authMode?: string;
      expiresAt?: string;
      refreshToken?: string;
      oidcIssuer?: string;
      oidcClientID?: string;
      createdAt?: string;
    };

export function oauthCredentialIsExpired(credential: AccountCredential, at: Date): boolean {
  switch (credential.kind) {
    case "codex":
    case "kimi":
      return credential.oauth.expiresAt
        ? new Date(credential.oauth.expiresAt).getTime() <= at.getTime()
        : false;
    default:
      return false;
  }
}

// ---------------------------------------------------------------------------
// Refresh state (per account)
// ---------------------------------------------------------------------------

export interface AccountRefreshState {
  lastRequestStartedAt: string | null;
  providerRetryAt: string | null;
  failureBackoffUntil: string | null;
  consecutiveTransientFailures: number;
  requiresReauthentication: boolean;
}

export function initialRefreshState(): AccountRefreshState {
  return {
    lastRequestStartedAt: null,
    providerRetryAt: null,
    failureBackoffUntil: null,
    consecutiveTransientFailures: 0,
    requiresReauthentication: false,
  };
}

// ---------------------------------------------------------------------------
// Persisted app state
// ---------------------------------------------------------------------------

export type UsageSectionID =
  | "short"
  | "daily"
  | "weekly"
  | "monthly"
  | "custom"
  | "extra-credits";

export interface PersistedAppState {
  accounts: SubscriptionAccount[];
  snapshots: Record<string, UsageSnapshot>;
  refreshStates: Record<string, AccountRefreshState>;
  isFloatingWidgetVisible: boolean;
  floatingWidgetPlacement: { x: number; y: number; width: number; height: number } | null;
  collapsedUsageSections: UsageSectionID[];
}

export function emptyPersistedState(): PersistedAppState {
  return {
    accounts: [],
    snapshots: {},
    refreshStates: {},
    isFloatingWidgetVisible: false,
    floatingWidgetPlacement: null,
    collapsedUsageSections: [],
  };
}
