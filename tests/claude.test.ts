import { describe, expect, it } from "vitest";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import {
  claudeAPICookies,
  decodeClaudeOrganizations,
  decodeClaudeUsage,
} from "../src/core/providers/claude.js";
import { hexOfUTF8 } from "../src/core/dates.js";
import { isProviderClientError } from "../src/core/errors.js";

const fixture = (name: string): Uint8Array =>
  new Uint8Array(readFileSync(join(__dirname, "fixtures", name)));

const ACCOUNT = "10000000-0000-0000-0000-0000000000aa";
const FETCHED = new Date("2026-07-29T18:00:00Z");

describe("decodeClaudeUsage", () => {
  it("decodes the qualified fixture: legacy windows + scoped weekly limit", () => {
    const snapshot = decodeClaudeUsage(fixture("claude-usage.json"), ACCOUNT, FETCHED);

    expect(snapshot.accountID).toBe(ACCOUNT);
    expect(snapshot.fetchedAt).toBe(FETCHED.toISOString());
    expect(snapshot.balances).toEqual([]);

    const [short, weekly, scoped] = snapshot.windows;
    expect(snapshot.windows).toHaveLength(3);

    expect(short).toMatchObject({
      id: "five-hour",
      kind: "short",
      duration: 18_000,
      consumedFraction: 0.81,
      resetAt: "2026-07-29T20:23:00.000Z",
    });
    expect(weekly).toMatchObject({
      id: "seven-day",
      kind: "weekly",
      duration: 604_800,
      consumedFraction: 0.66,
      resetAt: "2026-08-03T21:40:00.000Z",
    });
    // Scoped weekly entry for model "Fable" (id null → name identity);
    // unscoped and non-weekly-group entries are skipped.
    expect(scoped).toMatchObject({
      id: `claude-weekly-scoped-${hexOfUTF8("name:Fable")}`,
      kind: "weekly",
      duration: 604_800,
      consumedFraction: 0.42,
      label: "Fable",
    });
  });

  it("rejects responses without the legacy windows", () => {
    const payload = JSON.stringify({ five_hour: { utilization: 10 } });
    try {
      decodeClaudeUsage(new TextEncoder().encode(payload), ACCOUNT, FETCHED);
      expect.unreachable();
    } catch (error) {
      expect(isProviderClientError(error, "unsupportedResponse")).toBe(true);
    }
  });

  it("rejects out-of-range utilization", () => {
    const payload = JSON.stringify({
      five_hour: { utilization: 140, resets_at: "2026-07-29T20:23:00Z" },
      seven_day: { utilization: 10, resets_at: "2026-08-03T21:40:00Z" },
    });
    try {
      decodeClaudeUsage(new TextEncoder().encode(payload), ACCOUNT, FETCHED);
      expect.unreachable();
    } catch (error) {
      expect(isProviderClientError(error, "unsupportedResponse")).toBe(true);
    }
  });

  it("survives a malformed limits container (scoped surface is optional)", () => {
    const payload = JSON.stringify({
      five_hour: { utilization: 1, resets_at: "2026-07-29T20:23:00Z" },
      seven_day: { utilization: 2, resets_at: "2026-08-03T21:40:00Z" },
      limits: { "not": "an array" },
    });
    const snapshot = decodeClaudeUsage(new TextEncoder().encode(payload), ACCOUNT, FETCHED);
    expect(snapshot.windows).toHaveLength(2);
  });

  it("skips malformed scoped entries but keeps valid ones", () => {
    const payload = JSON.stringify({
      five_hour: { utilization: 1, resets_at: "2026-07-29T20:23:00Z" },
      seven_day: { utilization: 2, resets_at: "2026-08-03T21:40:00Z" },
      limits: [
        { group: "weekly", percent: 55, resets_at: "2026-08-03T21:40:00Z", scope: { model: { id: "m1", display_name: "Opus" } } },
        { group: "weekly", percent: 999, resets_at: "2026-08-03T21:40:00Z", scope: { model: { id: "m2", display_name: "Bad" } } },
        "garbage",
      ],
    });
    const snapshot = decodeClaudeUsage(new TextEncoder().encode(payload), ACCOUNT, FETCHED);
    expect(snapshot.windows).toHaveLength(3);
    expect(snapshot.windows[2]).toMatchObject({
      id: `claude-weekly-scoped-${hexOfUTF8("id:m1")}`,
      label: "Opus",
      consumedFraction: 0.55,
    });
  });

  it("colliding scoped ids resolve to the higher-consumed entry", () => {
    const payload = JSON.stringify({
      five_hour: { utilization: 1, resets_at: "2026-07-29T20:23:00Z" },
      seven_day: { utilization: 2, resets_at: "2026-08-03T21:40:00Z" },
      limits: [
        { group: "weekly", percent: 20, resets_at: "2026-08-03T21:40:00Z", scope: { model: { display_name: "Fable" } } },
        { group: "weekly", percent: 42, resets_at: "2026-08-03T21:40:00Z", scope: { model: { display_name: "Fable" } } },
      ],
    });
    const snapshot = decodeClaudeUsage(new TextEncoder().encode(payload), ACCOUNT, FETCHED);
    expect(snapshot.windows).toHaveLength(3);
    expect(snapshot.windows[2]!.consumedFraction).toBe(0.42);
  });

  it("decodes a spend balance with exponent scaling", () => {
    const payload = JSON.stringify({
      five_hour: { utilization: 1, resets_at: "2026-07-29T20:23:00Z" },
      seven_day: { utilization: 2, resets_at: "2026-08-03T21:40:00Z" },
      spend: { enabled: true, balance: { amount_minor: 3842, currency: "USD", exponent: 2 } },
    });
    const snapshot = decodeClaudeUsage(new TextEncoder().encode(payload), ACCOUNT, FETCHED);
    expect(snapshot.balances).toHaveLength(1);
    expect(snapshot.balances[0]).toMatchObject({
      id: "claude-usage-credits",
      label: "Usage credits",
      value: { state: "available", amount: 38.42, unit: "USD" },
    });
  });

  it("reports credits disabled when extra usage is off", () => {
    for (const extra of [
      { extra_usage: { is_enabled: false, user_disabled: false } },
      { extra_usage: { is_enabled: true, user_disabled: true } },
      { spend: { enabled: false } },
    ]) {
      const payload = JSON.stringify({
        five_hour: { utilization: 1, resets_at: "2026-07-29T20:23:00Z" },
        seven_day: { utilization: 2, resets_at: "2026-08-03T21:40:00Z" },
        ...extra,
      });
      const snapshot = decodeClaudeUsage(new TextEncoder().encode(payload), ACCOUNT, FETCHED);
      expect(snapshot.balances[0]!.value).toEqual({ state: "disabled" });
    }
  });
});

describe("decodeClaudeOrganizations", () => {
  it("decodes the organizations fixture", () => {
    const orgs = decodeClaudeOrganizations(fixture("claude-organizations.json"));
    expect(orgs).toEqual([
      {
        uuid: "10000000-0000-0000-0000-000000000001",
        name: "Personal",
        capabilities: ["chat", "claude_max"],
      },
    ]);
  });

  it("rejects an empty organization list", () => {
    try {
      decodeClaudeOrganizations(new TextEncoder().encode("[]"));
      expect.unreachable();
    } catch (error) {
      expect(isProviderClientError(error, "unsupportedResponse")).toBe(true);
    }
  });
});

describe("claudeAPICookies", () => {
  const cookie = (name: string, domain = "claude.ai", value = "v") => ({
    name,
    value,
    domain,
  });

  it("requires sessionKey and rides cf_clearance/__cf_bm", () => {
    const selected = claudeAPICookies([
      cookie("sessionKey"),
      cookie("cf_clearance"),
      cookie("__cf_bm"),
      cookie("unrelated"),
      cookie("sessionKey", "other.com"),
    ]);
    expect(selected?.map((c) => c.name).sort()).toEqual([
      "__cf_bm",
      "cf_clearance",
      "sessionKey",
    ]);
  });

  it("returns null without sessionKey", () => {
    expect(claudeAPICookies([cookie("cf_clearance")])).toBeNull();
  });
});
