import { describe, expect, it } from "vitest";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import {
  applyCodexRefresh,
  codexAuthorizationURL,
  codexRefreshRequest,
  codexTokenExchangeRequest,
  decodeCodexInitialToken,
  decodeCodexUsage,
  CODEX_CLIENT_ID,
} from "../src/core/providers/codex.js";
import { isProviderClientError } from "../src/core/errors.js";
import { base64URLEncode } from "../src/core/dates.js";

const fixture = (name: string): Uint8Array =>
  new Uint8Array(readFileSync(join(__dirname, "fixtures", name)));

const ACCOUNT = "10000000-0000-0000-0000-0000000000bb";
const FETCHED = new Date("2026-07-29T18:00:00Z");

function makeJWT(payload: Record<string, unknown>): string {
  const segment = (value: unknown) =>
    base64URLEncode(new TextEncoder().encode(JSON.stringify(value)));
  return `${segment({ alg: "none" })}.${segment(payload)}.${segment({})}`;
}

describe("decodeCodexUsage", () => {
  it("decodes the fixture: weekly primary + short secondary + credits", () => {
    const snapshot = decodeCodexUsage(fixture("codex-usage.json"), ACCOUNT, FETCHED);

    expect(snapshot.windows).toHaveLength(2);
    const [short, weekly] = snapshot.windows;
    expect(short).toMatchObject({
      id: "codex-short",
      kind: "short",
      duration: 18_000,
      consumedFraction: 0.81,
      resetAt: new Date(2_000_010_000 * 1000).toISOString(),
    });
    expect(weekly).toMatchObject({
      id: "codex-weekly",
      kind: "weekly",
      duration: 604_800,
      consumedFraction: 0.66,
      resetAt: new Date(2_000_020_000 * 1000).toISOString(),
    });

    expect(snapshot.balances).toEqual([
      {
        id: "codex-chatgpt-credits",
        label: "ChatGPT credits",
        value: { state: "available", amount: 1240.5, unit: "credits" },
        cycleEndsAt: null,
      },
    ]);
  });

  it("maps unlimited credits", () => {
    const payload = JSON.stringify({
      rate_limit: {
        primary_window: { used_percent: 1, limit_window_seconds: 18000, reset_at: 2_000_010_000 },
      },
      credits: { has_credits: true, unlimited: true },
    });
    const snapshot = decodeCodexUsage(new TextEncoder().encode(payload), ACCOUNT, FETCHED);
    expect(snapshot.balances[0]!.value).toEqual({ state: "unlimited" });
  });

  it("maps missing credits to disabled", () => {
    const payload = JSON.stringify({
      rate_limit: {
        primary_window: { used_percent: 1, limit_window_seconds: 18000, reset_at: 2_000_010_000 },
      },
      credits: { has_credits: false, unlimited: false },
    });
    const snapshot = decodeCodexUsage(new TextEncoder().encode(payload), ACCOUNT, FETCHED);
    expect(snapshot.balances[0]!.value).toEqual({ state: "disabled" });
  });

  it("rejects when no recognized windows exist", () => {
    const payload = JSON.stringify({
      rate_limit: {
        primary_window: { used_percent: 1, limit_window_seconds: 86_400, reset_at: 2_000_010_000 },
      },
    });
    try {
      decodeCodexUsage(new TextEncoder().encode(payload), ACCOUNT, FETCHED);
      expect.unreachable();
    } catch (error) {
      expect(isProviderClientError(error, "unsupportedResponse")).toBe(true);
    }
  });

  it("rejects a duplicate kind across primary/secondary", () => {
    const payload = JSON.stringify({
      rate_limit: {
        primary_window: { used_percent: 1, limit_window_seconds: 18000, reset_at: 2_000_010_000 },
        secondary_window: { used_percent: 2, limit_window_seconds: 18000, reset_at: 2_000_010_000 },
      },
    });
    try {
      decodeCodexUsage(new TextEncoder().encode(payload), ACCOUNT, FETCHED);
      expect.unreachable();
    } catch (error) {
      expect(isProviderClientError(error, "unsupportedResponse")).toBe(true);
    }
  });
});

describe("codex OAuth requests", () => {
  it("builds the authorization URL with the codex CLI parameters", () => {
    const url = new URL(
      codexAuthorizationURL({
        redirectURL: "http://localhost:1455/auth/callback",
        codeChallenge: "challenge",
        state: "state-value",
      }),
    );
    expect(url.origin + url.pathname).toBe("https://auth.openai.com/oauth/authorize");
    const params = url.searchParams;
    expect(params.get("response_type")).toBe("code");
    expect(params.get("client_id")).toBe(CODEX_CLIENT_ID);
    expect(params.get("redirect_uri")).toBe("http://localhost:1455/auth/callback");
    expect(params.get("scope")).toBe(
      "openid profile email offline_access api.connectors.read api.connectors.invoke",
    );
    expect(params.get("code_challenge")).toBe("challenge");
    expect(params.get("code_challenge_method")).toBe("S256");
    expect(params.get("id_token_add_organizations")).toBe("true");
    expect(params.get("codex_cli_simplified_flow")).toBe("true");
    expect(params.get("state")).toBe("state-value");
    expect(params.get("originator")).toBe("codex_cli_rs");
    expect(params.get("prompt")).toBe("select_account");
  });

  it("builds the form-encoded token exchange", () => {
    const request = codexTokenExchangeRequest({
      code: "the-code",
      redirectURL: "http://localhost:1455/auth/callback",
      verifier: "the-verifier",
    });
    expect(request.url).toBe("https://auth.openai.com/oauth/token");
    expect(request.headers["Content-Type"]).toBe("application/x-www-form-urlencoded");
    const body = new URLSearchParams(request.body as string);
    expect(body.get("grant_type")).toBe("authorization_code");
    expect(body.get("code")).toBe("the-code");
    expect(body.get("redirect_uri")).toBe("http://localhost:1455/auth/callback");
    expect(body.get("client_id")).toBe(CODEX_CLIENT_ID);
    expect(body.get("code_verifier")).toBe("the-verifier");
  });

  it("builds the JSON refresh request", () => {
    const request = codexRefreshRequest("refresh-me");
    expect(request.headers["Content-Type"]).toBe("application/json");
    expect(JSON.parse(request.body as string)).toEqual({
      client_id: CODEX_CLIENT_ID,
      grant_type: "refresh_token",
      refresh_token: "refresh-me",
    });
  });
});

describe("codex token decoding", () => {
  const idToken = makeJWT({
    email: "user@example.com",
    "https://api.openai.com/auth": {
      chatgpt_plan_type: "plus",
      chatgpt_user_id: "user-1",
      chatgpt_account_id: "account-1",
    },
  });

  it("decodes the initial token response with identity claims", () => {
    const result = decodeCodexInitialToken(
      new TextEncoder().encode(
        JSON.stringify({
          access_token: makeJWT({ exp: 2_000_000_000 }),
          refresh_token: "refresh",
          id_token: idToken,
        }),
      ),
    );
    expect(result.identity).toEqual({
      email: "user@example.com",
      plan: "plus",
      userID: "user-1",
      accountID: "account-1",
    });
    expect(result.credential.refreshToken).toBe("refresh");
    expect(result.credential.accountID).toBe("account-1");
    expect(result.credential.expiresAt).toBe(
      new Date(2_000_000_000 * 1000).toISOString(),
    );
  });

  it("applies a refresh, preserving fields absent from the response", () => {
    const original = decodeCodexInitialToken(
      new TextEncoder().encode(
        JSON.stringify({
          access_token: makeJWT({ exp: 2_000_000_000 }),
          refresh_token: "refresh",
          id_token: idToken,
        }),
      ),
    );
    const refreshed = applyCodexRefresh(
      new TextEncoder().encode(JSON.stringify({ access_token: makeJWT({ exp: 2_100_000_000 }) })),
      original,
    );
    expect(refreshed.credential.refreshToken).toBe("refresh");
    expect(refreshed.credential.accountID).toBe("account-1");
    expect(refreshed.credential.expiresAt).toBe(
      new Date(2_100_000_000 * 1000).toISOString(),
    );
    expect(refreshed.identity.email).toBe("user@example.com");
  });

  it("rejects malformed responses", () => {
    try {
      decodeCodexInitialToken(new TextEncoder().encode("{}"));
      expect.unreachable();
    } catch (error) {
      expect(isProviderClientError(error, "unsupportedResponse")).toBe(true);
    }
  });
});
