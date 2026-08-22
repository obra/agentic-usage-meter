import { describe, expect, it } from "vitest";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { decodeZaiUsage } from "../src/core/providers/zai.js";
import { isProviderClientError } from "../src/core/errors.js";

const fixture = (name: string): Uint8Array =>
  new Uint8Array(readFileSync(join(__dirname, "fixtures", name)));

const ACCOUNT = "10000000-0000-0000-0000-000000000011";
const FETCHED = new Date("2026-07-29T18:00:00Z");

describe("decodeZaiUsage", () => {
  it("decodes the fixture: TOKENS_LIMIT u3/n5 → short, u6/n1 → weekly", () => {
    const snapshot = decodeZaiUsage(fixture("zai-quota-limit.json"), ACCOUNT, FETCHED);
    expect(snapshot.windows).toHaveLength(2);

    // The TIME_LIMIT entry (with usageDetails) is ignored.
    const [short, weekly] = snapshot.windows;
    expect(short).toMatchObject({
      id: "zai-short",
      kind: "short",
      duration: 18_000,
      consumedFraction: 0.375,
      resetAt: new Date(1_785_912_345_678).toISOString(),
    });
    expect(weekly).toMatchObject({
      id: "zai-weekly",
      kind: "weekly",
      duration: 604_800,
      consumedFraction: 0.12,
      resetAt: new Date(1_785_998_765_432).toISOString(),
    });
  });

  it("maps embedded 401/403 codes to reauthenticationRequired", () => {
    for (const code of [401, 403]) {
      try {
        decodeZaiUsage(
          new TextEncoder().encode(JSON.stringify({ code, success: false })),
          ACCOUNT,
          FETCHED,
        );
        expect.unreachable();
      } catch (error) {
        expect(isProviderClientError(error, "reauthenticationRequired")).toBe(true);
      }
    }
  });

  it("rejects unsuccessful responses", () => {
    try {
      decodeZaiUsage(
        new TextEncoder().encode(JSON.stringify({ code: 500, success: false })),
        ACCOUNT,
        FETCHED,
      );
      expect.unreachable();
    } catch (error) {
      expect(isProviderClientError(error, "unsupportedResponse")).toBe(true);
    }
  });

  it("accepts a zero-percent window without a reset time", () => {
    const payload = JSON.stringify({
      code: 200,
      success: true,
      data: {
        limits: [
          { type: "TOKENS_LIMIT", unit: 3, number: 5, percentage: 0, nextResetTime: 0 },
        ],
      },
    });
    const snapshot = decodeZaiUsage(new TextEncoder().encode(payload), ACCOUNT, FETCHED);
    expect(snapshot.windows[0]).toMatchObject({
      id: "zai-short",
      consumedFraction: 0,
      resetAt: null,
    });
  });

  it("rejects out-of-range percentages", () => {
    const payload = JSON.stringify({
      code: 200,
      success: true,
      data: {
        limits: [
          { type: "TOKENS_LIMIT", unit: 3, number: 5, percentage: 120, nextResetTime: 1 },
        ],
      },
    });
    try {
      decodeZaiUsage(new TextEncoder().encode(payload), ACCOUNT, FETCHED);
      expect.unreachable();
    } catch (error) {
      expect(isProviderClientError(error, "unsupportedResponse")).toBe(true);
    }
  });
});
