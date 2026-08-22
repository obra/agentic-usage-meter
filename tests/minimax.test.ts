import { describe, expect, it } from "vitest";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { decodeMiniMaxUsage } from "../src/core/providers/minimax.js";
import { isProviderClientError } from "../src/core/errors.js";

const fixture = (name: string): Uint8Array =>
  new Uint8Array(readFileSync(join(__dirname, "fixtures", name)));

const ACCOUNT = "10000000-0000-0000-0000-0000000000ee";
const FETCHED = new Date("2026-07-29T18:00:00Z");

describe("decodeMiniMaxUsage", () => {
  it("decodes the fixture, preferring the row with usable quotas", () => {
    const snapshot = decodeMiniMaxUsage(fixture("minimax-usage.json"), ACCOUNT, FETCHED);
    expect(snapshot.windows).toHaveLength(2);

    // The first row has zero totals (no quota); the second row wins.
    // NB: `current_*_usage_count` is the REMAINING count in this API.
    const [short, weekly] = snapshot.windows;
    expect(short).toMatchObject({
      id: "minimax-short",
      kind: "short",
      duration: 18_000,
      consumedFraction: 0.5, // (1500 - 750) / 1500
      resetAt: new Date(1_774_605_600_000).toISOString(),
      reportedStartAt: new Date(1_774_587_600_000).toISOString(),
    });
    expect(weekly).toMatchObject({
      id: "minimax-weekly",
      kind: "weekly",
      duration: 604_800,
      consumedFraction: 0.6, // (15000 - 6000) / 15000
      resetAt: new Date(1_774_828_800_000).toISOString(),
      reportedStartAt: new Date(1_774_224_000_000).toISOString(),
    });
  });

  it("accepts string-encoded numbers and status_code", () => {
    const payload = JSON.stringify({
      model_remains: [
        {
          start_time: "1774587600000",
          end_time: "1774605600000",
          current_interval_total_count: "100",
          current_interval_usage_count: "25",
          model_name: "M",
        },
      ],
      base_resp: { status_code: "0" },
    });
    const snapshot = decodeMiniMaxUsage(new TextEncoder().encode(payload), ACCOUNT, FETCHED);
    expect(snapshot.windows[0]).toMatchObject({ consumedFraction: 0.75 });
  });

  it("rejects a nonzero base status", () => {
    const payload = JSON.stringify({
      model_remains: [],
      base_resp: { status_code: 1002 },
    });
    try {
      decodeMiniMaxUsage(new TextEncoder().encode(payload), ACCOUNT, FETCHED);
      expect.unreachable();
    } catch (error) {
      expect(isProviderClientError(error, "unsupportedResponse")).toBe(true);
    }
  });

  it("rejects when no model row yields a quota", () => {
    const payload = JSON.stringify({
      model_remains: [{ model_name: "empty" }],
      base_resp: { status_code: 0 },
    });
    try {
      decodeMiniMaxUsage(new TextEncoder().encode(payload), ACCOUNT, FETCHED);
      expect.unreachable();
    } catch (error) {
      expect(isProviderClientError(error, "unsupportedResponse")).toBe(true);
    }
  });
});
