import { describe, expect, it } from "vitest";
import {
  AccountRefresher,
  RefreshCoordinator,
  DEVELOPMENT_REFRESH_POLICY,
  RELEASE_REFRESH_POLICY,
} from "../src/core/refresh/refresh.js";
import { ProviderClientError } from "../src/core/errors.js";
import { initialRefreshState, type UsageSnapshot } from "../src/core/models.js";

const ACCOUNT = "10000000-0000-0000-0000-000000000055";
const T0 = new Date("2026-07-29T18:00:00Z");

const snapshot = (tag = "ok"): UsageSnapshot => ({
  accountID: ACCOUNT,
  fetchedAt: `${T0.toISOString()}-${tag}`,
  windows: [],
  balances: [],
});

describe("refresh policies", () => {
  it("development policy refreshes every minute", () => {
    expect(DEVELOPMENT_REFRESH_POLICY.automaticInterval).toBe(60);
    expect(DEVELOPMENT_REFRESH_POLICY.minimumProviderInterval).toBe(60);
  });

  it("release policy refreshes every ten minutes", () => {
    expect(RELEASE_REFRESH_POLICY.automaticInterval).toBe(600);
    expect(RELEASE_REFRESH_POLICY.minimumProviderInterval).toBe(600);
  });
});

describe("AccountRefresher", () => {
  it("rejects a non-positive minimum interval", () => {
    expect(() => new AccountRefresher(0)).toThrow();
    expect(() => new AccountRefresher(-5)).toThrow();
  });

  it("first refresh succeeds and clears failure state", async () => {
    let now = T0;
    const refresher = new AccountRefresher(60, initialRefreshState(), null, () => now);
    const outcome = await refresher.refresh(async () => snapshot());
    expect(outcome).toEqual({ type: "refreshed", snapshot: snapshot() });
    expect(refresher.refreshState().lastRequestStartedAt).toBe(T0.toISOString());
  });

  it("throttles a second refresh inside the minimum interval", async () => {
    let now = T0;
    const refresher = new AccountRefresher(60, initialRefreshState(), null, () => now);
    const first = await refresher.refresh(async () => snapshot("1"));
    expect(first.type).toBe("refreshed");

    now = new Date(T0.getTime() + 30_000);
    const outcome = await refresher.refresh(async () => snapshot("2"));
    expect(outcome.type).toBe("throttled");
    if (outcome.type === "throttled") {
      expect(outcome.eligibleAt.getTime()).toBe(T0.getTime() + 60_000);
      expect(outcome.snapshot).toEqual(snapshot("1"));
    }
  });

  it("refreshes again once the minimum interval has elapsed", async () => {
    let now = T0;
    const refresher = new AccountRefresher(60, initialRefreshState(), null, () => now);
    await refresher.refresh(async () => snapshot("1"));
    now = new Date(T0.getTime() + 61_000);
    const outcome = await refresher.refresh(async () => snapshot("2"));
    expect(outcome).toEqual({ type: "refreshed", snapshot: snapshot("2") });
  });

  it("coalesces concurrent refreshes into a single fetch", async () => {
    let fetches = 0;
    const refresher = new AccountRefresher(60, initialRefreshState(), null, () => T0);
    const [a, b] = await Promise.all([
      refresher.refresh(async () => {
        fetches += 1;
        return snapshot();
      }),
      refresher.refresh(async () => {
        fetches += 1;
        return snapshot();
      }),
    ]);
    expect(fetches).toBe(1);
    expect(a).toEqual(b);
  });

  it("reauthenticationRequired latches until credentials change", async () => {
    let now = T0;
    const refresher = new AccountRefresher(60, initialRefreshState(), null, () => now);
    const outcome = await refresher.refresh(async () => {
      throw ProviderClientError.reauthenticationRequired();
    });
    expect(outcome.type).toBe("reauthenticationRequired");
    expect(refresher.refreshState().requiresReauthentication).toBe(true);

    now = new Date(T0.getTime() + 120_000);
    const again = await refresher.refresh(async () => snapshot());
    expect(again.type).toBe("reauthenticationRequired");

    refresher.credentialsDidChange();
    expect(refresher.refreshState().requiresReauthentication).toBe(false);
    const recovered = await refresher.refresh(async () => snapshot());
    expect(recovered.type).toBe("refreshed");
  });

  it("retryingAuthentication bypasses the reauthentication latch", async () => {
    let now = T0;
    const refresher = new AccountRefresher(60, initialRefreshState(), null, () => now);
    await refresher.refresh(async () => {
      throw ProviderClientError.reauthenticationRequired();
    });
    now = new Date(T0.getTime() + 61_000); // auth retry still respects the throttle
    const outcome = await refresher.refresh(async () => snapshot(), true);
    expect(outcome.type).toBe("refreshed");
    expect(refresher.refreshState().requiresReauthentication).toBe(false);
  });

  it("temporary failures back off exponentially (600s → 1200s → 2400s)", async () => {
    let now = T0;
    const refresher = new AccountRefresher(60, initialRefreshState(), null, () => now);
    const fail = async (): Promise<UsageSnapshot> => {
      throw ProviderClientError.temporaryFailure();
    };

    const first = await refresher.refresh(fail);
    expect(first.type).toBe("failed");
    let state = refresher.refreshState();
    expect(state.consecutiveTransientFailures).toBe(1);
    expect(new Date(state.failureBackoffUntil!).getTime()).toBe(T0.getTime() + 600_000);

    now = new Date(T0.getTime() + 601_000);
    const second = await refresher.refresh(fail);
    expect(second.type).toBe("failed");
    state = refresher.refreshState();
    expect(state.consecutiveTransientFailures).toBe(2);
    expect(new Date(state.failureBackoffUntil!).getTime()).toBe(
      now.getTime() + 1_200_000,
    );

    now = new Date(now.getTime() + 1_201_000);
    const third = await refresher.refresh(fail);
    expect(third.type).toBe("failed");
    state = refresher.refreshState();
    expect(state.consecutiveTransientFailures).toBe(3);
    expect(new Date(state.failureBackoffUntil!).getTime()).toBe(
      now.getTime() + 2_400_000,
    );
  });

  it("backoff caps at one hour after enough consecutive failures", async () => {
    let now = T0;
    const refresher = new AccountRefresher(60, initialRefreshState(), null, () => now);
    const fail = async (): Promise<UsageSnapshot> => {
      throw ProviderClientError.temporaryFailure();
    };
    for (let i = 0; i < 5; i += 1) {
      const outcome = await refresher.refresh(fail);
      expect(outcome.type).toBe("failed");
      const until = new Date(refresher.refreshState().failureBackoffUntil!);
      now = new Date(until.getTime() + 1_000);
    }
    const state = refresher.refreshState();
    expect(state.consecutiveTransientFailures).toBe(5);
    // Exponent is capped at 3 → 600 * 8 = 4800s, then capped at 3600s.
    const backoffMs =
      new Date(state.failureBackoffUntil!).getTime() -
      new Date(state.lastRequestStartedAt!).getTime();
    expect(backoffMs).toBe(3_600_000);
  });

  it("retryAfter honors the provider-supplied retry date", async () => {
    const retryAt = new Date(T0.getTime() + 45_000);
    const refresher = new AccountRefresher(60, initialRefreshState(), null, () => T0);
    const outcome = await refresher.refresh(async () => {
      throw ProviderClientError.retryAfter(retryAt);
    });
    expect(outcome.type).toBe("failed");
    if (outcome.type === "failed") {
      expect(outcome.eligibleAt.getTime()).toBeGreaterThanOrEqual(retryAt.getTime());
    }
    expect(refresher.refreshState().providerRetryAt).toBe(retryAt.toISOString());
  });

  it("a successful refresh resets the failure counters and keeps the last good snapshot on failure", async () => {
    let now = T0;
    const refresher = new AccountRefresher(60, initialRefreshState(), null, () => now);
    await refresher.refresh(async () => snapshot("good"));
    now = new Date(now.getTime() + 61_000);
    const failed = await refresher.refresh(async () => {
      throw ProviderClientError.temporaryFailure();
    });
    expect(failed.type).toBe("failed");
    if (failed.type === "failed") {
      expect(failed.snapshot).toEqual(snapshot("good"));
    }
    now = new Date(new Date(refresher.refreshState().failureBackoffUntil!).getTime() + 1_000);
    const recovered = await refresher.refresh(async () => snapshot("new"));
    expect(recovered.type).toBe("refreshed");
    const state = refresher.refreshState();
    expect(state.consecutiveTransientFailures).toBe(0);
    expect(state.failureBackoffUntil).toBeNull();
    expect(state.providerRetryAt).toBeNull();
  });

  it("subscriptionRequired and unsupportedResponse propagate instead of being classified", async () => {
    const refresher = new AccountRefresher(60, initialRefreshState(), null, () => T0);
    await expect(
      refresher.refresh(async () => {
        throw ProviderClientError.subscriptionRequired();
      }),
    ).rejects.toSatisfy((error) => error === ProviderClientError.subscriptionRequired() || (error as Error).name === "ProviderClientError");

    const refresher2 = new AccountRefresher(60, initialRefreshState(), null, () => T0);
    await expect(
      refresher2.refresh(async () => {
        throw ProviderClientError.unsupportedResponse();
      }),
    ).rejects.toMatchObject({ name: "ProviderClientError", kind: "unsupportedResponse" });
    expect(refresher2.refreshState().requiresReauthentication).toBe(false);
  });
});

describe("RefreshCoordinator", () => {
  it("rejects a non-positive concurrency limit", () => {
    expect(() => new RefreshCoordinator(0)).toThrow();
  });

  it("runs every account with at most N operations in flight", async () => {
    const coordinator = new RefreshCoordinator(2);
    let active = 0;
    let maxActive = 0;
    const seen: string[] = [];
    await coordinator.run(["a", "b", "c", "d", "e"], async (id) => {
      active += 1;
      maxActive = Math.max(maxActive, active);
      await new Promise((resolve) => setTimeout(resolve, 10));
      seen.push(id);
      active -= 1;
    });
    expect(seen.sort()).toEqual(["a", "b", "c", "d", "e"]);
    expect(maxActive).toBe(2);
  });

  it("releases the slot when an operation throws", async () => {
    const coordinator = new RefreshCoordinator(1);
    await expect(
      coordinator.run(["a"], async () => {
        throw new Error("boom");
      }),
    ).rejects.toThrow("boom");
    // A subsequent run must not deadlock: the slot was released.
    const seen: string[] = [];
    await coordinator.run(["b"], async (id) => {
      seen.push(id);
    });
    expect(seen).toEqual(["b"]);
  });
});
