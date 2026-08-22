import { describe, expect, it } from "vitest";
import {
  decodeSuperGrokAuthDocument,
  decodeSuperGrokUsage,
  SuperGrokDeviceAuthOutputParser,
  SuperGrokOIDCRefreshClient,
  superGrokHasRefreshMaterial,
  superGrokIdentityKey,
  superGrokNeedsRefresh,
} from "../src/core/providers/supergrok.js";
import { isProviderClientError } from "../src/core/errors.js";
import { HTTPResponse, type HTTPTransport } from "../src/core/http.js";

const ACCOUNT = "10000000-0000-0000-0000-000000000044";
const FETCHED = new Date("2026-07-29T18:00:00Z");
const encode = (text: string) => new TextEncoder().encode(text);

describe("decodeSuperGrokUsage", () => {
  it("decodes a weekly current period with prepaid balance", () => {
    const payload = JSON.stringify({
      config: {
        creditUsagePercent: 35,
        currentPeriod: {
          type: "USAGE_PERIOD_TYPE_WEEKLY",
          start: "2026-07-27T00:00:00Z",
          end: "2026-08-03T00:00:00Z",
        },
        prepaidBalance: { val: 1299 },
      },
    });
    const snapshot = decodeSuperGrokUsage(encode(payload), ACCOUNT, FETCHED);
    expect(snapshot.windows[0]).toMatchObject({
      id: "supergrok-weekly",
      kind: "weekly",
      duration: 604_800,
      consumedFraction: 0.35,
      resetAt: "2026-08-03T00:00:00.000Z",
      reportedStartAt: "2026-07-27T00:00:00.000Z",
    });
    expect(snapshot.balances[0]).toMatchObject({
      id: "supergrok-prepaid",
      label: "Extra usage",
      value: { state: "available", amount: 12.99, unit: "USD" },
    });
  });

  it("falls back to the legacy monthlyLimit/used shape", () => {
    const payload = JSON.stringify({
      config: {
        monthlyLimit: { val: 5000 },
        used: { val: 1250 },
        billingPeriodStart: "2026-07-01T00:00:00Z",
        billingPeriodEnd: "2026-08-01T00:00:00Z",
      },
    });
    const snapshot = decodeSuperGrokUsage(encode(payload), ACCOUNT, FETCHED);
    expect(snapshot.windows[0]).toMatchObject({
      id: "supergrok-monthly",
      kind: "monthly",
      consumedFraction: 0.25,
    });
  });

  it("rejects configs with no usable window", () => {
    try {
      decodeSuperGrokUsage(encode('{"config":{}}'), ACCOUNT, FETCHED);
      expect.unreachable();
    } catch (error) {
      expect(isProviderClientError(error, "unsupportedResponse")).toBe(true);
    }
  });
});

describe("decodeSuperGrokAuthDocument", () => {
  it("decodes a flat auth.json", () => {
    const credential = decodeSuperGrokAuthDocument(
      encode(
        JSON.stringify({
          key: "tok",
          email: "user@x.ai",
          user_id: "u1",
          team_id: "t1",
          auth_mode: "oidc",
          expires_at: "2026-08-01T00:00:00Z",
          refresh_token: "rt",
          oidc_issuer: "https://auth.x.ai",
          oidc_client_id: "cid",
          create_time: "2026-07-01T00:00:00Z",
        }),
      ),
    );
    expect(credential).toMatchObject({
      accessToken: "tok",
      email: "user@x.ai",
      userID: "u1",
      teamID: "t1",
      authMode: "oidc",
      refreshToken: "rt",
      oidcIssuer: "https://auth.x.ai",
      oidcClientID: "cid",
    });
  });

  it("prefers the auth.x.ai scope when the document is keyed by issuer", () => {
    const credential = decodeSuperGrokAuthDocument(
      encode(
        JSON.stringify({
          "https://other.example.com": { key: "other", user_id: "ux" },
          "https://auth.x.ai::xai": { key: "xai-token", user_id: "u1" },
        }),
      ),
    );
    expect(credential.accessToken).toBe("xai-token");
  });

  it("requires a user id", () => {
    try {
      decodeSuperGrokAuthDocument(encode('{"key":"tok"}'));
      expect.unreachable();
    } catch (error) {
      expect(isProviderClientError(error, "unsupportedResponse")).toBe(true);
    }
  });
});

describe("credential helpers", () => {
  it("identity key prefers user::team", () => {
    expect(
      superGrokIdentityKey({ accessToken: "a", userID: " U ", teamID: "T", email: "e@x.ai" }),
    ).toBe("u::t");
    expect(superGrokIdentityKey({ accessToken: "a", email: "E@x.ai " })).toBe("e@x.ai");
  });

  it("refresh material requires oidc mode + token + issuer + client id", () => {
    const base = {
      accessToken: "a",
      authMode: "oidc",
      refreshToken: "r",
      oidcIssuer: "https://auth.x.ai",
      oidcClientID: "c",
    };
    expect(superGrokHasRefreshMaterial(base)).toBe(true);
    expect(superGrokHasRefreshMaterial({ ...base, authMode: "api_key" })).toBe(false);
    expect(superGrokHasRefreshMaterial({ ...base, refreshToken: " " })).toBe(false);
  });

  it("needsRefresh: 5-minute skew on expiry, 30 days on creation", () => {
    const now = new Date("2026-07-29T18:00:00Z");
    expect(
      superGrokNeedsRefresh(
        { accessToken: "a", expiresAt: "2026-07-29T18:04:00Z" },
        now,
      ),
    ).toBe(true);
    expect(
      superGrokNeedsRefresh(
        { accessToken: "a", expiresAt: "2026-07-29T18:06:00Z" },
        now,
      ),
    ).toBe(false);
    expect(
      superGrokNeedsRefresh(
        { accessToken: "a", createdAt: "2026-06-29T17:00:00Z" },
        now,
      ),
    ).toBe(true);
    expect(superGrokNeedsRefresh({ accessToken: "a" }, now)).toBe(false);
  });
});

describe("SuperGrokDeviceAuthOutputParser", () => {
  it("extracts the verification URL and user code from CLI output", () => {
    const parser = new SuperGrokDeviceAuthOutputParser();
    expect(parser.append("Opening https://x.ai/device\n")).toBeNull();
    const prompt = parser.append("Enter code AB12-CD34 to continue\n");
    expect(prompt).toEqual({
      verificationURL: "https://x.ai/device",
      userCode: "AB12-CD34",
    });
  });
});

describe("SuperGrokOIDCRefreshClient", () => {
  const jsonResponse = (status: number, body: unknown) =>
    new HTTPResponse(encode(JSON.stringify(body)), status, {});
  const queueTransport = (responses: HTTPResponse[]): HTTPTransport => {
    const queue = [...responses];
    return {
      send: async () => {
        const next = queue.shift();
        if (!next) throw new Error("unexpected request");
        return next;
      },
    };
  };

  const credential = {
    accessToken: "old",
    userID: "u1",
    authMode: "oidc",
    refreshToken: "rt",
    oidcIssuer: "https://auth.x.ai",
    oidcClientID: "cid",
  };

  it("discovers the token endpoint and applies the refresh", async () => {
    const transport = queueTransport([
      jsonResponse(200, { token_endpoint: "https://auth.x.ai/oauth/token" }),
      jsonResponse(200, { access_token: "new", expires_in: 3600, refresh_token: "rt2" }),
    ]);
    const client = new SuperGrokOIDCRefreshClient(transport);
    const refreshed = await client.refresh(credential, FETCHED);
    expect(refreshed.accessToken).toBe("new");
    expect(refreshed.refreshToken).toBe("rt2");
    expect(refreshed.expiresAt).toBe(
      new Date(FETCHED.getTime() + 3_600_000).toISOString(),
    );
    expect(refreshed.createdAt).toBe(FETCHED.toISOString());
  });

  it("rejects a token endpoint on another host", async () => {
    const transport = queueTransport([
      jsonResponse(200, { token_endpoint: "https://evil.example.com/token" }),
    ]);
    const client = new SuperGrokOIDCRefreshClient(transport);
    try {
      await client.refresh(credential, FETCHED);
      expect.unreachable();
    } catch (error) {
      expect(isProviderClientError(error, "unsupportedResponse")).toBe(true);
    }
  });

  it("maps invalid_grant to reauthenticationRequired", async () => {
    const transport = queueTransport([
      jsonResponse(200, { token_endpoint: "https://auth.x.ai/oauth/token" }),
      jsonResponse(400, { error: "invalid_grant" }),
    ]);
    const client = new SuperGrokOIDCRefreshClient(transport);
    await expect(client.refresh(credential, FETCHED)).rejects.toSatisfy((error) =>
      isProviderClientError(error, "reauthenticationRequired"),
    );
  });
});
