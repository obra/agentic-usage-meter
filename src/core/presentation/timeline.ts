// Presentation — port of TimelineLayout.swift, UsageWindowPresentation.swift
// and UsageSummary.swift. Produces plain, IPC-serializable view models.

import {
  windowRemainingFraction,
  windowStartAt,
  type SubscriptionAccount,
  type UsageBalance,
  type UsageSnapshot,
  type UsageWindow,
  type UsageWindowKind,
  type UsageSectionID,
} from "../models.js";
import { providerDefinition, providerSortIndex } from "../catalog.js";
import { formatDayTime } from "../dates.js";

// ---------------------------------------------------------------------------
// TimelineLayout
// ---------------------------------------------------------------------------

export interface TimelineLayout {
  start: Date;
  end: Date;
}

export function makeTimelineLayout(duration: number, now: Date): TimelineLayout | null {
  if (!Number.isFinite(duration) || duration <= 0) return null;
  return {
    start: new Date(now.getTime() - duration * 1000),
    end: new Date(now.getTime() + duration * 1000),
  };
}

function clamp01(value: number): number {
  return Math.min(Math.max(value, 0), 1);
}

export function layoutXFraction(layout: TimelineLayout, window: UsageWindow): number {
  const span = layout.end.getTime() - layout.start.getTime();
  const start = windowStartAt(window) ?? new Date(layout.start.getTime() + span / 2);
  return clamp01((start.getTime() - layout.start.getTime()) / span);
}

export function layoutWidthFraction(layout: TimelineLayout, window: UsageWindow): number {
  const span = layout.end.getTime() - layout.start.getTime();
  return clamp01((window.duration * 1000) / span);
}

// ---------------------------------------------------------------------------
// View-model types
// ---------------------------------------------------------------------------

export interface AccountViewState {
  account: SubscriptionAccount;
  snapshot: UsageSnapshot | null;
  error: "requiresReauthentication" | "temporarilyUnavailable" | null;
  isRefreshing: boolean;
  nextEligibleAt: string | null;
}

export interface WindowRowPresentation {
  id: string; // accountID:windowID
  accountID: string;
  provider: SubscriptionAccount["provider"];
  providerText: string;
  accountText: string;
  outerXFraction: number;
  outerWidthFraction: number;
  fillFraction: number;
  // Fill anchors to the reset edge so remaining quota reads against
  // remaining time; a fill reaching the now-line is on budget.
  fillXFraction: number;
  nowXFraction: number;
  remainingPercentageText: string;
  relativeResetText: string;
  exactResetText: string | null;
  helpText: string;
}

export interface SectionPresentation {
  kind: UsageWindowKind;
  rows: WindowRowPresentation[];
}

export interface BalanceRowPresentation {
  id: string; // accountID:balance:balanceID
  accountID: string;
  provider: SubscriptionAccount["provider"];
  providerText: string;
  accountText: string;
  labelText: string;
  valueText: string;
  cycleEndText: string | null;
}

export interface TimelinePresentation {
  sections: SectionPresentation[];
  balanceRows: BalanceRowPresentation[];
}

export const WINDOW_KIND_PRESENTATION_ORDER: UsageWindowKind[] = [
  "short",
  "daily",
  "weekly",
  "monthly",
  "custom",
];

export function defaultAxisDuration(
  kind: UsageWindowKind,
  customDuration: number,
): number {
  switch (kind) {
    case "short":
      return 18_000;
    case "daily":
      return 86_400;
    case "weekly":
      return 604_800;
    case "monthly":
      return 2_678_400;
    case "custom":
      return customDuration;
  }
}

export function sectionIDForKind(kind: UsageWindowKind): UsageSectionID {
  return kind;
}

export const SECTION_TITLES: Record<UsageSectionID, string> = {
  short: "5-hour windows",
  daily: "Daily windows",
  weekly: "Weekly windows",
  monthly: "Monthly windows",
  custom: "Other windows",
  "extra-credits": "Extra Credits",
};

// ---------------------------------------------------------------------------
// Row presentation
// ---------------------------------------------------------------------------

function usageIdentity(account: SubscriptionAccount): {
  providerText: string;
  accountText: string;
} {
  return {
    providerText: providerDefinition(account.provider).displayName,
    accountText: account.displayName.trim(),
  };
}

export function relativeResetText(now: Date, resetAt: Date): string {
  const interval = (resetAt.getTime() - now.getTime()) / 1000;
  if (interval <= 0) return "Now";
  const totalMinutes = Math.floor(interval / 60);
  if (totalMinutes < 60) return `${totalMinutes}m`;
  const totalHours = Math.floor(totalMinutes / 60);
  const minutes = totalMinutes % 60;
  if (totalHours < 24) return `${totalHours}h ${minutes}m`;
  const days = Math.floor(totalHours / 24);
  const hours = totalHours % 24;
  return `${days}d ${hours}h`;
}

export function windowRowPresentation(input: {
  account: SubscriptionAccount;
  window: UsageWindow;
  now: Date;
  timeZone?: string;
  axisDuration?: number;
  showsWindowLabel?: boolean;
}): WindowRowPresentation {
  const { account, window, now } = input;
  const showsWindowLabel = input.showsWindowLabel ?? false;
  const identity = usageIdentity(account);
  const accountText =
    showsWindowLabel && window.label
      ? `${window.label} · ${identity.accountText}`
      : identity.accountText;

  const axisDuration =
    input.axisDuration ?? defaultAxisDuration(window.kind, window.duration);
  const layout = makeTimelineLayout(axisDuration, now)!;
  const outerXFraction = layoutXFraction(layout, window);
  const outerWidthFraction = layoutWidthFraction(layout, window);
  const fillFraction = windowRemainingFraction(window);
  const fillXFraction = outerXFraction + outerWidthFraction * (1 - fillFraction);

  const remainingPercent = Math.round(fillFraction * 100);
  let relative: string;
  let exactResetText: string | null;
  let helpText: string;
  if (window.resetAt) {
    const resetAt = new Date(window.resetAt);
    relative = relativeResetText(now, resetAt);
    exactResetText = formatDayTime(resetAt, input.timeZone);
    helpText = `Resets ${exactResetText}`;
  } else {
    relative = relativeResetText(now, new Date(now.getTime() + window.duration * 1000));
    exactResetText = null;
    helpText = "No provider reset reported";
  }

  return {
    id: `${account.id}:${window.id}`,
    accountID: account.id,
    provider: account.provider,
    providerText: identity.providerText,
    accountText,
    outerXFraction,
    outerWidthFraction,
    fillFraction,
    fillXFraction,
    nowXFraction: 0.5,
    remainingPercentageText: `${remainingPercent}%`,
    relativeResetText: relative,
    exactResetText,
    helpText,
  };
}

// ---------------------------------------------------------------------------
// Sections
// ---------------------------------------------------------------------------

function accountStateComesBefore(lhs: AccountViewState, rhs: AccountViewState): number {
  const lhsProvider = providerSortIndex(lhs.account.provider);
  const rhsProvider = providerSortIndex(rhs.account.provider);
  if (lhsProvider !== rhsProvider) return lhsProvider - rhsProvider;
  if (lhs.account.displayOrder !== rhs.account.displayOrder) {
    return lhs.account.displayOrder - rhs.account.displayOrder;
  }
  return lhs.account.id < rhs.account.id ? -1 : lhs.account.id > rhs.account.id ? 1 : 0;
}

export function sectionPresentation(
  kind: UsageWindowKind,
  accounts: AccountViewState[],
  now: Date,
  timeZone?: string,
): SectionPresentation {
  const matching = accounts
    .slice()
    .sort(accountStateComesBefore)
    .flatMap((state) => {
      const windows = state.snapshot?.windows ?? [];
      const showsFactoryCore =
        state.account.provider === "factory" &&
        windows.some(
          (window) => window.label === "Droid Core" && window.consumedFraction > 0,
        );
      return windows
        .filter((window) => window.kind === kind)
        .filter(
          (window) =>
            state.account.provider !== "factory" ||
            window.label !== "Droid Core" ||
            showsFactoryCore,
        )
        .map((window) => ({ account: state.account, window }));
    });

  const axisDuration = defaultAxisDuration(
    kind,
    Math.max(1, ...matching.map((item) => item.window.duration)),
  );
  const windowCounts = new Map<string, number>();
  for (const item of matching) {
    windowCounts.set(item.account.id, (windowCounts.get(item.account.id) ?? 0) + 1);
  }
  const rows = matching.map((item) =>
    windowRowPresentation({
      account: item.account,
      window: item.window,
      now,
      ...(timeZone ? { timeZone } : {}),
      axisDuration,
      showsWindowLabel: (windowCounts.get(item.account.id) ?? 0) > 1,
    }),
  );
  return { kind, rows };
}

// ---------------------------------------------------------------------------
// Balances
// ---------------------------------------------------------------------------

export function formatBalanceAmount(amount: number, unit: string): string {
  if (unit.length === 3 && /^[A-Za-z]{3}$/.test(unit)) {
    try {
      return new Intl.NumberFormat("en-US", {
        style: "currency",
        currency: unit.toUpperCase(),
      }).format(amount);
    } catch {
      return `${amount} ${unit}`;
    }
  }
  const formatted = new Intl.NumberFormat("en-US", {
    style: "decimal",
    maximumFractionDigits: 8,
  }).format(amount);
  return `${formatted} ${unit}`;
}

export function balanceRowPresentation(input: {
  account: SubscriptionAccount;
  balance: UsageBalance;
  timeZone?: string;
}): BalanceRowPresentation {
  const { account, balance } = input;
  const identity = usageIdentity(account);
  let valueText: string;
  switch (balance.value.state) {
    case "available":
      valueText = formatBalanceAmount(balance.value.amount, balance.value.unit);
      break;
    case "unlimited":
      valueText = "Unlimited";
      break;
    case "disabled":
      valueText = "Off";
      break;
  }
  let cycleEndText: string | null = null;
  if (balance.cycleEndsAt) {
    cycleEndText = formatDayTime(new Date(balance.cycleEndsAt), input.timeZone);
  }
  return {
    id: `${account.id}:balance:${balance.id}`,
    accountID: account.id,
    provider: account.provider,
    providerText: identity.providerText,
    accountText: identity.accountText,
    labelText: balance.label,
    valueText,
    cycleEndText,
  };
}

export function timelinePresentation(
  accounts: AccountViewState[],
  now: Date,
  timeZone?: string,
): TimelinePresentation {
  const sections = WINDOW_KIND_PRESENTATION_ORDER.map((kind) =>
    sectionPresentation(kind, accounts, now, timeZone),
  ).filter((section) => section.rows.length > 0);

  const balanceRows = accounts
    .slice()
    .sort(accountStateComesBefore)
    .flatMap((state) =>
      (state.snapshot?.balances ?? []).map((balance) =>
        balanceRowPresentation({ account: state.account, balance, ...(timeZone ? { timeZone } : {}) }),
      ),
    );
  return { sections, balanceRows };
}

// ---------------------------------------------------------------------------
// Summary (tray label)
// ---------------------------------------------------------------------------

export interface TightestUsage {
  accountID: string;
  window: UsageWindow;
}

export function tightestWindow(snapshots: UsageSnapshot[]): TightestUsage | null {
  const all = snapshots.flatMap((snapshot) =>
    snapshot.windows.map((window) => ({ accountID: snapshot.accountID, window })),
  );
  if (all.length === 0) return null;
  return all.reduce((tightest, candidate) => {
    const lhs = candidate.window;
    const rhs = tightest.window;
    const lhsRemaining = windowRemainingFraction(lhs);
    const rhsRemaining = windowRemainingFraction(rhs);
    if (lhsRemaining !== rhsRemaining) {
      return lhsRemaining < rhsRemaining ? candidate : tightest;
    }
    if (lhs.resetAt && rhs.resetAt) {
      return lhs.resetAt < rhs.resetAt ? candidate : tightest;
    }
    if (lhs.resetAt && !rhs.resetAt) return candidate;
    if (!lhs.resetAt && rhs.resetAt) return tightest;
    return lhs.id < rhs.id ? candidate : tightest;
  });
}

// The tray label text mirrors the macOS menu-bar summary: remaining percent
// of the tightest window, or null when no snapshots exist.
export function traySummaryText(snapshots: UsageSnapshot[]): string | null {
  const tightest = tightestWindow(snapshots);
  if (!tightest) return null;
  return `${Math.round(windowRemainingFraction(tightest.window) * 100)}%`;
}
