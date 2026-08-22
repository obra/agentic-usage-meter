import { describe, expect, it } from "vitest";
import {
  decodeOpenCodeGoUsage,
  decodeOpenCodeZenUsage,
  htmlNumber,
  htmlObjectBody,
  normalizeDashboardHTML,
  openCodeAuthCookie,
  openCodeWorkspaceID,
} from "../src/core/providers/opencode.js";
import { isProviderClientError } from "../src/core/errors.js";

const ACCOUNT = "10000000-0000-0000-0000-000000000033";
const FETCHED = new Date("2026-07-29T18:00:00Z");

const encode = (text: string) => new TextEncoder().encode(text);

describe("dashboard HTML helpers", () => {
  it("unescapes HTML/JS string encodings", () => {
    const html = normalizeDashboardHTML(
      encode("&quot;balance&quot;: &#34;5&#34; \\u0022x\\u0022"),
    );
    expect(htmlNumber("balance", html)).toBe(5);
  });

  it("extracts object bodies and numbers", () => {
    const body = htmlObjectBody("rollingUsage", '{"rollingUsage":{"usagePercent":42,"resetInSec":3600}}');
    expect(body).toBe('"usagePercent":42,"resetInSec":3600');
    expect(htmlNumber("usagePercent", body!)).toBe(42);
  });
});

describe("decodeOpenCodeGoUsage", () => {
  it("decodes embedded JSON fields (rolling/weekly/monthly)", () => {
    const html = JSON.stringify({
      rollingUsage: { usagePercent: 30, resetInSec: 3600 },
      weeklyUsage: { usagePercent: 55.5, resetInSec: 86400 },
      monthlyUsage: { usagePercent: 10, resetInSec: 5 * 86400 },
    });
    const snapshot = decodeOpenCodeGoUsage(encode(JSON.parse(html) ? html : html), ACCOUNT, FETCHED);
    expect(snapshot.windows).toHaveLength(3);

    const [rolling, weekly, monthly] = snapshot.windows;
    expect(rolling).toMatchObject({
      id: "opencode-go-rolling",
      kind: "short",
      duration: 18_000,
      consumedFraction: 0.3,
      resetAt: new Date(FETCHED.getTime() + 3_600_000).toISOString(),
    });
    expect(weekly).toMatchObject({
      id: "opencode-go-weekly",
      kind: "weekly",
      duration: 604_800,
      consumedFraction: 0.555,
    });
    expect(monthly).toMatchObject({
      id: "opencode-go-monthly",
      kind: "monthly",
      consumedFraction: 0.1,
    });
    // Monthly duration derives from the reset date (a calendar month back).
    const monthlyReset = new Date(monthly!.resetAt!);
    expect(monthly!.duration).toBeGreaterThan(27 * 86_400);
    expect(monthlyReset.getTime()).toBe(FETCHED.getTime() + 5 * 86_400_000);
  });

  it("falls back to data-slot markup", () => {
    const html = `
      <div data-slot="usage-item">
        <span data-slot="usage-label">Rolling usage</span>
        <span data-slot="usage-value">72%</span>
        <span data-slot="reset-time">1 hour 30 minutes</span>
      </div>
      <div data-slot="usage-item">
        <span data-slot="usage-label">Weekly usage</span>
        <span data-slot="usage-value">40%</span>
        <span data-slot="reset-time">2 days</span>
      </div>`;
    const snapshot = decodeOpenCodeGoUsage(encode(html), ACCOUNT, FETCHED);
    expect(snapshot.windows).toHaveLength(2);
    expect(snapshot.windows[0]).toMatchObject({
      id: "opencode-go-rolling",
      consumedFraction: 0.72,
      resetAt: new Date(FETCHED.getTime() + 5_400_000).toISOString(),
    });
    expect(snapshot.windows[1]).toMatchObject({
      id: "opencode-go-weekly",
      consumedFraction: 0.4,
      resetAt: new Date(FETCHED.getTime() + 2 * 86_400_000).toISOString(),
    });
  });

  it("reset-now means the window resets immediately", () => {
    const html = `
      <div data-slot="usage-item">
        <span data-slot="usage-label">Rolling usage</span>
        <span data-slot="usage-value">10%</span>
        <span data-slot="reset-now">now</span>
      </div>`;
    const snapshot = decodeOpenCodeGoUsage(encode(html), ACCOUNT, FETCHED);
    expect(snapshot.windows[0]!.resetAt).toBe(FETCHED.toISOString());
  });

  it("detects the no-subscription page", () => {
    const html = `<div data-slot="subscribe-button"></div><script>{"subscriptionPlan":null}</script>`;
    try {
      decodeOpenCodeGoUsage(encode(html), ACCOUNT, FETCHED);
      expect.unreachable();
    } catch (error) {
      expect(isProviderClientError(error, "subscriptionRequired")).toBe(true);
    }
  });

  it("rejects pages with no usage data", () => {
    try {
      decodeOpenCodeGoUsage(encode("<html><body>nothing</body></html>"), ACCOUNT, FETCHED);
      expect.unreachable();
    } catch (error) {
      expect(isProviderClientError(error, "unsupportedResponse")).toBe(true);
    }
  });
});

describe("decodeOpenCodeZenUsage", () => {
  it("decodes balance + monthly window within the current cycle", () => {
    const html = JSON.stringify({
      balance: 12_340_000_000, // microcents → $123.40
      monthlyLimit: 50, // dollars
      monthlyUsage: 2_000_000_000, // $20
      timeMonthlyUsageUpdated: "2026-07-01T00:00:01Z",
    });
    const snapshot = decodeOpenCodeZenUsage(encode(html), ACCOUNT, FETCHED);
    expect(snapshot.balances[0]).toMatchObject({
      id: "opencode-zen-balance",
      value: { state: "available", amount: 123.4, unit: "USD" },
    });
    expect(snapshot.windows[0]).toMatchObject({
      id: "opencode-zen-monthly",
      kind: "monthly",
      resetAt: "2026-08-01T00:00:00.000Z",
      consumedFraction: 0.4,
    });
  });

  it("zeroes usage reported before the current cycle (stale timestamp)", () => {
    const html = JSON.stringify({
      balance: 100_000_000,
      monthlyLimit: 50,
      monthlyUsage: 2_000_000_000,
      timeMonthlyUsageUpdated: "2026-06-15T00:00:00Z",
    });
    const snapshot = decodeOpenCodeZenUsage(encode(html), ACCOUNT, FETCHED);
    expect(snapshot.windows[0]!.consumedFraction).toBe(0);
  });

  it("trusts reported usage when no update timestamp is present", () => {
    const html = JSON.stringify({
      balance: 100_000_000,
      monthlyLimit: 50,
      monthlyUsage: 1_000_000_000,
    });
    const snapshot = decodeOpenCodeZenUsage(encode(html), ACCOUNT, FETCHED);
    expect(snapshot.windows[0]!.consumedFraction).toBe(0.2);
  });

  it("omits the window when there is no monthly limit", () => {
    const snapshot = decodeOpenCodeZenUsage(encode('{"balance": 500000000}'), ACCOUNT, FETCHED);
    expect(snapshot.windows).toEqual([]);
    expect(snapshot.balances[0]!.value).toEqual({
      state: "available",
      amount: 5,
      unit: "USD",
    });
  });
});

describe("login detection", () => {
  it("extracts the workspace id from workspace URLs", () => {
    expect(openCodeWorkspaceID("https://opencode.ai/workspace/abc123/go")).toBe("abc123");
    expect(openCodeWorkspaceID("https://app.opencode.ai/workspace/w%2042/billing")).toBe("w 42");
    expect(openCodeWorkspaceID("https://opencode.ai/settings")).toBeNull();
    expect(openCodeWorkspaceID("https://evil.com/workspace/abc/go")).toBeNull();
  });

  it("finds the auth cookie on opencode domains", () => {
    expect(
      openCodeAuthCookie([
        { name: "auth", value: "token", domain: ".opencode.ai" },
        { name: "auth", value: "other", domain: "example.com" },
      ]),
    ).toBe("token");
    expect(openCodeAuthCookie([{ name: "auth", value: "", domain: ".opencode.ai" }])).toBeNull();
  });
});
