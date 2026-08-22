import { describe, expect, it } from "vitest";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { decodeFactoryUsage } from "../src/core/providers/factory.js";
import { isProviderClientError } from "../src/core/errors.js";

const fixture = (name: string): Uint8Array =>
  new Uint8Array(readFileSync(join(__dirname, "fixtures", name)));

const ACCOUNT = "10000000-0000-0000-0000-0000000000ff";
const FETCHED = new Date("2026-07-29T18:00:00Z");

describe("decodeFactoryUsage", () => {
  it("decodes the fixture: two pools × three windows + USD balance", () => {
    const snapshot = decodeFactoryUsage(fixture("factory-limits.json"), ACCOUNT, FETCHED);
    expect(snapshot.windows).toHaveLength(6);

    const byID = new Map(snapshot.windows.map((window) => [window.id, window]));
    expect(byID.get("factory-standard-five-hour")).toMatchObject({
      kind: "short",
      duration: 18_000,
      consumedFraction: 0.225,
      resetAt: "2026-07-30T23:00:00.000Z",
      label: "Standard",
    });
    expect(byID.get("factory-standard-weekly")).toMatchObject({
      kind: "weekly",
      consumedFraction: 0.48,
      label: "Standard",
    });
    expect(byID.get("factory-standard-monthly")).toMatchObject({
      kind: "monthly",
      duration: 2_592_000,
      consumedFraction: 0.6125,
      label: "Standard",
    });
    expect(byID.get("factory-core-five-hour")).toMatchObject({
      consumedFraction: 0.07,
      label: "Droid Core",
      resetAt: "2026-07-30T22:30:00.000Z",
    });
    expect(byID.get("factory-core-weekly")).toMatchObject({ consumedFraction: 0.11 });
    expect(byID.get("factory-core-monthly")).toMatchObject({ consumedFraction: 0.19 });

    expect(snapshot.balances).toEqual([
      {
        id: "factory-extra-usage",
        label: "Extra usage",
        value: { state: "available", amount: 12.34, unit: "USD" },
        cycleEndsAt: null,
      },
    ]);
  });

  it("rejects responses without token rate limits billing", () => {
    const payload = JSON.stringify({ usesTokenRateLimitsBilling: false });
    try {
      decodeFactoryUsage(new TextEncoder().encode(payload), ACCOUNT, FETCHED);
      expect.unreachable();
    } catch (error) {
      expect(isProviderClientError(error, "unsupportedResponse")).toBe(true);
    }
  });

  it("maps extraUsageAllowed=false to a disabled balance", () => {
    const payload = JSON.stringify({
      usesTokenRateLimitsBilling: true,
      extraUsageAllowed: false,
    });
    const snapshot = decodeFactoryUsage(new TextEncoder().encode(payload), ACCOUNT, FETCHED);
    expect(snapshot.balances[0]!.value).toEqual({ state: "disabled" });
  });

  it("allows a zero-percent window without a windowEnd (no invented reset)", () => {
    const payload = JSON.stringify({
      usesTokenRateLimitsBilling: true,
      limits: {
        standard: { fiveHour: { usedPercent: 0, windowEnd: null } },
      },
      extraUsageAllowed: false,
    });
    const snapshot = decodeFactoryUsage(new TextEncoder().encode(payload), ACCOUNT, FETCHED);
    expect(snapshot.windows[0]).toMatchObject({
      id: "factory-standard-five-hour",
      consumedFraction: 0,
      resetAt: null,
    });
  });

  it("rejects a nonzero-percent window without windowEnd", () => {
    const payload = JSON.stringify({
      usesTokenRateLimitsBilling: true,
      limits: {
        standard: { fiveHour: { usedPercent: 10, windowEnd: null } },
      },
    });
    try {
      decodeFactoryUsage(new TextEncoder().encode(payload), ACCOUNT, FETCHED);
      expect.unreachable();
    } catch (error) {
      expect(isProviderClientError(error, "unsupportedResponse")).toBe(true);
    }
  });
});
