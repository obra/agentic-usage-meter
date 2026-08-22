// Refresh engine — port of AccountRefresher.swift, RefreshCoordinator.swift
// and RefreshPolicy.swift.

import {
  initialRefreshState,
  type AccountRefreshState,
  type UsageSnapshot,
} from "../models.js";
import { classifyRefreshFailure, isProviderClientError } from "../errors.js";

export interface RefreshPolicy {
  automaticInterval: number; // seconds
  minimumProviderInterval: number; // seconds
}

export const DEVELOPMENT_REFRESH_POLICY: RefreshPolicy = {
  automaticInterval: 60,
  minimumProviderInterval: 60,
};

export const RELEASE_REFRESH_POLICY: RefreshPolicy = {
  automaticInterval: 600,
  minimumProviderInterval: 600,
};

export type RefreshOutcome =
  | { type: "refreshed"; snapshot: UsageSnapshot }
  | { type: "throttled"; snapshot: UsageSnapshot | null; eligibleAt: Date }
  | { type: "reauthenticationRequired"; snapshot: UsageSnapshot | null }
  | { type: "failed"; snapshot: UsageSnapshot | null; eligibleAt: Date };

export type SnapshotFetch = () => Promise<UsageSnapshot>;

export class AccountRefresher {
  private state: AccountRefreshState;
  private lastGoodSnapshot: UsageSnapshot | null;
  private inFlight: Promise<RefreshOutcome> | null = null;

  constructor(
    private readonly minimumInterval: number = RELEASE_REFRESH_POLICY.minimumProviderInterval,
    state?: AccountRefreshState,
    lastGoodSnapshot?: UsageSnapshot | null,
    private readonly now: () => Date = () => new Date(),
  ) {
    if (!Number.isFinite(minimumInterval) || minimumInterval <= 0) {
      throw new Error("minimumInterval must be positive");
    }
    this.state = state ?? initialRefreshState();
    this.lastGoodSnapshot = lastGoodSnapshot ?? null;
  }

  refreshState(): AccountRefreshState {
    return this.state;
  }

  credentialsDidChange(): void {
    this.state.lastRequestStartedAt = null;
    this.state.providerRetryAt = null;
    this.state.failureBackoffUntil = null;
    this.state.consecutiveTransientFailures = 0;
    this.state.requiresReauthentication = false;
  }

  async refresh(fetch: SnapshotFetch, retryingAuthentication = false): Promise<RefreshOutcome> {
    if (this.inFlight) return this.inFlight;

    if (this.state.requiresReauthentication && !retryingAuthentication) {
      return { type: "reauthenticationRequired", snapshot: this.lastGoodSnapshot };
    }

    const requestedAt = this.now();
    const eligibleAt = this.nextEligibleDate();
    if (requestedAt < eligibleAt) {
      return { type: "throttled", snapshot: this.lastGoodSnapshot, eligibleAt };
    }

    this.state.lastRequestStartedAt = requestedAt.toISOString();
    this.inFlight = this.run(fetch).finally(() => {
      this.inFlight = null;
    });
    return this.inFlight;
  }

  private async run(fetch: SnapshotFetch): Promise<RefreshOutcome> {
    try {
      const snapshot = await fetch();
      this.lastGoodSnapshot = snapshot;
      this.state.providerRetryAt = null;
      this.state.failureBackoffUntil = null;
      this.state.consecutiveTransientFailures = 0;
      this.state.requiresReauthentication = false;
      return { type: "refreshed", snapshot };
    } catch (error) {
      const failure = classifyRefreshFailure(error);
      if (failure?.type === "authenticationRequired") {
        this.state.providerRetryAt = null;
        this.state.failureBackoffUntil = null;
        this.state.consecutiveTransientFailures = 0;
        this.state.requiresReauthentication = true;
        return { type: "reauthenticationRequired", snapshot: this.lastGoodSnapshot };
      }
      if (failure?.type === "transient") {
        this.state.consecutiveTransientFailures += 1;
        this.state.providerRetryAt = failure.providerRetryAt
          ? failure.providerRetryAt.toISOString()
          : null;
        const exponent = Math.min(this.state.consecutiveTransientFailures - 1, 3);
        const backoff = Math.min(600 * 2 ** exponent, 3_600);
        this.state.failureBackoffUntil = new Date(
          this.now().getTime() + backoff * 1000,
        ).toISOString();
        return {
          type: "failed",
          snapshot: this.lastGoodSnapshot,
          eligibleAt: this.nextEligibleDate(),
        };
      }
      if (
        isProviderClientError(error, "subscriptionRequired") ||
        isProviderClientError(error, "unsupportedResponse")
      ) {
        this.state.requiresReauthentication = false;
      }
      throw error;
    }
  }

  private nextEligibleDate(): Date {
    const candidates: number[] = [];
    if (this.state.lastRequestStartedAt) {
      candidates.push(
        new Date(this.state.lastRequestStartedAt).getTime() + this.minimumInterval * 1000,
      );
    }
    if (this.state.providerRetryAt) {
      candidates.push(new Date(this.state.providerRetryAt).getTime());
    }
    if (this.state.failureBackoffUntil) {
      candidates.push(new Date(this.state.failureBackoffUntil).getTime());
    }
    return candidates.length > 0 ? new Date(Math.max(...candidates)) : new Date(0);
  }
}

// Port of RefreshCoordinator: run an operation per account with bounded
// concurrency (FIFO waiters).
export class RefreshCoordinator {
  private active = 0;
  private readonly waiters: (() => void)[] = [];

  constructor(private readonly maximumConcurrentRefreshes = 3) {
    if (maximumConcurrentRefreshes <= 0) {
      throw new Error("maximumConcurrentRefreshes must be positive");
    }
  }

  private acquire(): Promise<void> {
    if (this.active < this.maximumConcurrentRefreshes) {
      this.active += 1;
      return Promise.resolve();
    }
    return new Promise((resolve) => this.waiters.push(resolve));
  }

  private release(): void {
    const next = this.waiters.shift();
    if (next) {
      next();
    } else {
      this.active -= 1;
    }
  }

  async run(accountIDs: string[], operation: (accountID: string) => Promise<void>): Promise<void> {
    await Promise.all(
      accountIDs.map(async (accountID) => {
        await this.acquire();
        try {
          await operation(accountID);
        } finally {
          this.release();
        }
      }),
    );
  }
}
