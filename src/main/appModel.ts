// AppModel — main-process port of the macOS AppModel: owns accounts,
// snapshots, per-account refreshers, the refresh loop, and persistence.

import { EventEmitter } from "node:events";
import { randomUUID, createHash } from "node:crypto";
import os from "node:os";
import {
  emptyPersistedState,
  initialRefreshState,
  type AccountRefreshState,
  type AccountCredential,
  type PersistedAppState,
  type Provider,
  type SubscriptionAccount,
  type UsageSectionID,
  type UsageSnapshot,
} from "../core/models.js";
import {
  AccountRefresher,
  RefreshCoordinator,
  type RefreshOutcome,
  type RefreshPolicy,
  RELEASE_REFRESH_POLICY,
} from "../core/refresh/refresh.js";
import type { AccountViewState } from "../core/presentation/timeline.js";
import {
  ProviderAdapters,
  type AdapterEnvironment,
  type CookieSource,
} from "../core/providers/index.js";
import { saveCredential, type CredentialStore } from "../core/credentials.js";
import { FetchHTTPTransport } from "../core/http.js";
import type { KimiDeviceInfo } from "../core/providers/kimi.js";
import type { AppStateStore } from "./storage.js";

export interface AppModelOptions {
  stateStore: AppStateStore;
  credentialStore: CredentialStore;
  cookieSource: CookieSource;
  refreshPolicy: RefreshPolicy;
  isSampleData: boolean;
}

export class AppModel extends EventEmitter {
  readonly isSampleData: boolean;
  private state: PersistedAppState = emptyPersistedState();
  private readonly refreshers = new Map<string, AccountRefresher>();
  private readonly refreshing = new Set<string>();
  private readonly adapters: ProviderAdapters;
  private readonly coordinator = new RefreshCoordinator(3);
  private readonly policy: RefreshPolicy;
  private autoRefreshTimer: NodeJS.Timeout | null = null;
  private saveQueued = false;

  constructor(private readonly options: AppModelOptions) {
    super();
    this.isSampleData = options.isSampleData;
    this.policy = options.refreshPolicy;
    const env: AdapterEnvironment = {
      transport: new FetchHTTPTransport(true),
      noRedirectTransport: new FetchHTTPTransport(false),
      credentialStore: options.credentialStore,
      cookieSource: options.cookieSource,
      kimiDevice: (accountID) => kimiDeviceForAccount(accountID),
      now: () => new Date(),
    };
    this.adapters = new ProviderAdapters(env);
  }

  async start(): Promise<void> {
    this.state = await this.options.stateStore.load();
    for (const account of this.state.accounts) {
      this.refresherFor(account.id);
    }
    this.emitChanged();
  }

  startAutomaticRefresh(): void {
    if (this.isSampleData || this.autoRefreshTimer) return;
    const tick = async () => {
      await this.refreshAllAccounts();
    };
    // First tick immediately (each refresher throttles to its own
    // eligibility), then on the policy interval.
    void tick();
    this.autoRefreshTimer = setInterval(() => void tick(), this.policy.automaticInterval * 1000);
    this.autoRefreshTimer.unref?.();
  }

  stopAutomaticRefresh(): void {
    if (this.autoRefreshTimer) clearInterval(this.autoRefreshTimer);
    this.autoRefreshTimer = null;
  }

  get accounts(): AccountViewState[] {
    return this.state.accounts
      .slice()
      .sort(compareAccounts)
      .map((account) => this.viewStateFor(account));
  }

  get snapshots(): UsageSnapshot[] {
    return this.state.accounts
      .map((account) => this.state.snapshots[account.id])
      .filter((snapshot): snapshot is UsageSnapshot => snapshot != null);
  }

  get collapsedSections(): UsageSectionID[] {
    return this.state.collapsedUsageSections;
  }

  get isFloatingWidgetVisible(): boolean {
    return this.state.isFloatingWidgetVisible;
  }

  get anyRefreshing(): boolean {
    return this.refreshing.size > 0;
  }

  account(accountID: string): SubscriptionAccount | undefined {
    return this.state.accounts.find((account) => account.id === accountID);
  }

  private viewStateFor(account: SubscriptionAccount): AccountViewState {
    const refreshState = this.state.refreshStates[account.id];
    let error: AccountViewState["error"] = null;
    if (refreshState?.requiresReauthentication) {
      error = "requiresReauthentication";
    } else if (
      refreshState &&
      refreshState.consecutiveTransientFailures > 0 &&
      !this.state.snapshots[account.id]
    ) {
      error = "temporarilyUnavailable";
    }
    return {
      account,
      snapshot: this.state.snapshots[account.id] ?? null,
      error,
      isRefreshing: this.refreshing.has(account.id),
      nextEligibleAt: null,
    };
  }

  private refresherFor(accountID: string): AccountRefresher {
    let refresher = this.refreshers.get(accountID);
    if (!refresher) {
      refresher = new AccountRefresher(
        this.policy.minimumProviderInterval,
        this.state.refreshStates[accountID] ?? initialRefreshState(),
        this.state.snapshots[accountID] ?? null,
      );
      this.refreshers.set(accountID, refresher);
    }
    return refresher;
  }

  async refreshAllAccounts(): Promise<void> {
    const ids = this.state.accounts.map((account) => account.id);
    await this.coordinator.run(ids, async (id) => {
      await this.refreshAccount(id);
    });
  }

  async refreshAccount(accountID: string): Promise<RefreshOutcome | null> {
    const account = this.account(accountID);
    if (!account) return null;
    const refresher = this.refresherFor(accountID);
    this.refreshing.add(accountID);
    this.emitChanged();
    try {
      const outcome = await refresher.refresh(async () => {
        const result = await this.adapters.fetchUsage(account);
        if (result.updatedCredential) {
          await saveCredential(
            this.options.credentialStore,
            result.updatedCredential,
            account.id,
          );
        }
        return result.snapshot;
      }, this.adapters.canRecoverAuthenticationWithoutReconnect(account.provider));
      this.applyOutcome(accountID, outcome);
      return outcome;
    } catch {
      // Hard failures (unsupportedResponse, subscriptionRequired,
      // credentialMismatch) surface as errors on the account.
      const refreshState = this.state.refreshStates[accountID];
      if (refreshState && !refreshState.requiresReauthentication) {
        // Keep the last-good snapshot; mark unavailable only when we have
        // never fetched successfully.
        if (!this.state.snapshots[accountID]) {
          refreshState.consecutiveTransientFailures = Math.max(
            1,
            refreshState.consecutiveTransientFailures,
          );
        }
      }
      return null;
    } finally {
      this.refreshing.delete(accountID);
      this.persistRefreshState(accountID);
      this.emitChanged();
      this.queueSave();
    }
  }

  private applyOutcome(accountID: string, outcome: RefreshOutcome): void {
    const refreshState = this.state.refreshStates[accountID] ?? initialRefreshState();
    switch (outcome.type) {
      case "refreshed":
        this.state.snapshots[accountID] = outcome.snapshot;
        Object.assign(refreshState, {
          providerRetryAt: null,
          failureBackoffUntil: null,
          consecutiveTransientFailures: 0,
          requiresReauthentication: false,
        });
        break;
      case "throttled":
        break;
      case "reauthenticationRequired":
        refreshState.requiresReauthentication = true;
        break;
      case "failed":
        break;
    }
    this.state.refreshStates[accountID] = this.refresherFor(accountID).refreshState();
  }

  private persistRefreshState(accountID: string): void {
    this.state.refreshStates[accountID] = this.refresherFor(accountID).refreshState();
  }

  async addAccount(
    account: Omit<SubscriptionAccount, "id"> & { id?: string },
    credential: AccountCredential | null,
  ): Promise<SubscriptionAccount> {
    const full: SubscriptionAccount = { ...account, id: account.id ?? randomUUID() };
    this.state.accounts.push(full);
    if (credential) {
      await saveCredential(this.options.credentialStore, credential, full.id);
    }
    this.refresherFor(full.id).credentialsDidChange();
    this.emitChanged();
    this.queueSave();
    // Fire an initial refresh without blocking the caller.
    void this.refreshAccount(full.id);
    return full;
  }

  async removeAccount(accountID: string): Promise<void> {
    const account = this.account(accountID);
    if (!account) return;
    await this.adapters.removeAuthentication(account);
    this.state.accounts = this.state.accounts.filter((entry) => entry.id !== accountID);
    delete this.state.snapshots[accountID];
    delete this.state.refreshStates[accountID];
    this.refreshers.delete(accountID);
    this.refreshing.delete(accountID);
    this.emitChanged();
    this.queueSave();
  }

  async reconnectAccount(accountID: string, credential: AccountCredential | null): Promise<void> {
    if (credential) {
      await saveCredential(this.options.credentialStore, credential, accountID);
    }
    this.refresherFor(accountID).credentialsDidChange();
    const refreshState = this.state.refreshStates[accountID];
    if (refreshState) refreshState.requiresReauthentication = false;
    this.emitChanged();
    void this.refreshAccount(accountID);
  }

  async toggleSection(section: UsageSectionID): Promise<void> {
    const set = new Set(this.state.collapsedUsageSections);
    if (set.has(section)) {
      set.delete(section);
    } else {
      set.add(section);
    }
    this.state.collapsedUsageSections = [...set];
    this.emitChanged();
    this.queueSave();
  }

  async setFloatingWidgetVisible(visible: boolean): Promise<void> {
    this.state.isFloatingWidgetVisible = visible;
    this.emitChanged();
    this.queueSave();
  }

  async setFloatingWidgetPlacement(
    placement: { x: number; y: number; width: number; height: number } | null,
  ): Promise<void> {
    this.state.floatingWidgetPlacement = placement;
    this.queueSave();
  }

  floatingWidgetPlacement() {
    return this.state.floatingWidgetPlacement;
  }

  private queueSave(): void {
    if (this.isSampleData || this.saveQueued) return;
    this.saveQueued = true;
    setTimeout(async () => {
      this.saveQueued = false;
      try {
        await this.options.stateStore.save(this.state);
      } catch (error) {
        console.error("Failed to persist state:", error);
      }
    }, 250).unref?.();
  }

  private emitChanged(): void {
    this.emit("changed");
  }
}

export function compareAccounts(
  lhs: SubscriptionAccount,
  rhs: SubscriptionAccount,
): number {
  if (lhs.displayOrder !== rhs.displayOrder) {
    return lhs.displayOrder - rhs.displayOrder;
  }
  return lhs.id < rhs.id ? -1 : lhs.id > rhs.id ? 1 : 0;
}

// Stable device identity per account, replacing KimiDeviceInfo.currentMac.
export function kimiDeviceForAccount(accountID: string): KimiDeviceInfo {
  const id = createHash("sha256").update(`agentic-usage-meter:${accountID}`).digest("hex").slice(0, 32);
  return {
    name: os.hostname() || "desktop",
    model: `${os.platform()}-${os.arch()}`,
    osVersion: os.release(),
    id,
    clientVersion: "0.1.0",
  };
}

// ---------------------------------------------------------------------------
// Sample data (--sample-data), ported from AgenticUsageMeterApp.sampleState.
// ---------------------------------------------------------------------------

export function samplePersistedState(showWidget = false): PersistedAppState {
  const now = new Date();
  const iso = (msFromNow: number) => new Date(now.getTime() + msFromNow).toISOString();

  const accountSpecs: [Provider, string, number][] = [
    ["claude", "Work", 0],
    ["claude", "Personal", 1],
    ["codex", "Work", 0],
    ["codex", "Personal", 1],
    ["kimi", "Kimi", 0],
    ["factory", "Factory", 0],
  ];

  const state = emptyPersistedState();
  accountSpecs.forEach(([provider, displayName, displayOrder], index) => {
    const account: SubscriptionAccount = {
      id: randomUUID(),
      provider,
      displayName,
      displayOrder,
    };
    state.accounts.push(account);

    const windows: UsageSnapshot["windows"] = [];
    const weeklyConsumed =
      provider === "kimi" ? 0.26 : Math.min(0.31 + index * 0.11, 0.9);
    if (provider === "factory") {
      for (const [poolID, label] of [
        ["standard", "Standard"],
        ["core", "Droid Core"],
      ] as const) {
        for (const [kind, duration] of [
          ["short", 18_000],
          ["weekly", 604_800],
          ["monthly", 2_592_000],
        ] as const) {
          windows.push({
            id: `${poolID}-${kind}`,
            kind,
            duration,
            resetAt: null,
            consumedFraction: 0,
            label,
            reportedStartAt: null,
          });
        }
      }
    } else {
      const weekly = {
        id: "weekly",
        kind: "weekly" as const,
        duration: 604_800,
        resetAt: iso((180_000 + index * 72_000) * 1000),
        consumedFraction: weeklyConsumed,
        label: null,
        reportedStartAt: null,
      };
      if (provider === "claude" || provider === "kimi") {
        windows.push({
          id: "short",
          kind: "short",
          duration: 18_000,
          resetAt: iso((3_000 + index * 1_500) * 1000),
          consumedFraction: Math.min(0.22 + index * 0.13, 0.92),
          label: null,
          reportedStartAt: null,
        });
      }
      windows.push(weekly);
    }

    const balances: UsageSnapshot["balances"] = [];
    if (provider === "claude" && displayOrder === 0) {
      balances.push({
        id: "extra-credits",
        label: "Extra usage",
        value: { state: "available", amount: 38.42, unit: "USD" },
        cycleEndsAt: null,
      });
    } else if (provider === "claude") {
      balances.push({
        id: "extra-credits",
        label: "Extra usage",
        value: { state: "disabled" },
        cycleEndsAt: null,
      });
    } else if (provider === "codex" && displayOrder === 0) {
      balances.push({
        id: "extra-credits",
        label: "Credits",
        value: { state: "available", amount: 1240.5, unit: "credits" },
        cycleEndsAt: null,
      });
    } else if (provider === "codex") {
      balances.push({
        id: "extra-credits",
        label: "Credits",
        value: { state: "unlimited" },
        cycleEndsAt: null,
      });
    } else if (provider === "kimi") {
      balances.push({
        id: "extra-credits",
        label: "Extra usage",
        value: { state: "disabled" },
        cycleEndsAt: null,
      });
    } else if (provider === "factory") {
      balances.push({
        id: "extra-credits",
        label: "Credits",
        value: { state: "available", amount: 0, unit: "USD" },
        cycleEndsAt: null,
      });
    }

    state.snapshots[account.id] = {
      accountID: account.id,
      fetchedAt: now.toISOString(),
      windows,
      balances,
    };
    const refreshState: AccountRefreshState = {
      ...initialRefreshState(),
      lastRequestStartedAt: now.toISOString(),
    };
    state.refreshStates[account.id] = refreshState;
  });
  state.isFloatingWidgetVisible = showWidget;
  return state;
}
