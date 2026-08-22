import { describe, expect, it } from "vitest";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { decodeMiMoUsage, mimoCookieHeader } from "../src/core/providers/mimo.js";
import { isProviderClientError } from "../src/core/errors.js";

const fixture = (name: string): Uint8Array =>
  new Uint8Array(readFileSync(join(__dirname, "fixtures", name)));

const ACCOUNT = "10000000-0000-0000-0000-000000000022";
const FETCHED = new Date("2026-07-29T18:00:00Z");

describe("decodeMiMoUsage", () => {
  it("decodes the fixture into a monthly token balance", () => {
    const snapshot = decodeMiMoUsage(fixture("mimo-token-plan-usage.json"), ACCOUNT, FETCHED);
    expect(snapshot.windows).toEqual([]);
    expect(snapshot.balances).toEqual([
      {
        id: "mimo-monthly-tokens",
        label: "Monthly tokens",
        value: {
          state: "available",
          amount: 82_000_000_000 - 8_582_309_279,
          unit: "tokens",
        },
        cycleEndsAt: null,
      },
    ]);
  });

  it("maps embedded 401/403 codes to reauthenticationRequired", () => {
    for (const code of [401, 403]) {
      try {
        decodeMiMoUsage(
          new TextEncoder().encode(JSON.stringify({ code })),
          ACCOUNT,
          FETCHED,
        );
        expect.unreachable();
      } catch (error) {
        expect(isProviderClientError(error, "reauthenticationRequired")).toBe(true);
      }
    }
  });

  it("rejects responses without the month_total_token bundle", () => {
    const payload = JSON.stringify({
      code: 0,
      data: { monthUsage: { items: [{ name: "other", used: 1, limit: 2 }] } },
    });
    try {
      decodeMiMoUsage(new TextEncoder().encode(payload), ACCOUNT, FETCHED);
      expect.unreachable();
    } catch (error) {
      expect(isProviderClientError(error, "unsupportedResponse")).toBe(true);
    }
  });
});

describe("mimoCookieHeader", () => {
  const NOW = new Date("2026-07-29T18:00:00Z");

  it("canonicalizes: sorted, unexpired, mimo domains only", () => {
    const header = mimoCookieHeader(
      [
        { name: "b", value: "2", domain: ".xiaomimimo.com" },
        { name: "a", value: "1", domain: "xiaomimimo.com" },
        { name: "x", value: "9", domain: "example.com" },
        {
          name: "expired",
          value: "e",
          domain: "xiaomimimo.com",
          expirationDate: NOW.getTime() / 1000 - 10,
        },
        { name: "empty", value: "", domain: "xiaomimimo.com" },
      ],
      NOW,
    );
    expect(header).toBe("a=1; b=2");
  });

  it("returns null when no usable cookies exist", () => {
    expect(mimoCookieHeader([{ name: "a", value: "1", domain: "example.com" }], NOW)).toBeNull();
  });
});
