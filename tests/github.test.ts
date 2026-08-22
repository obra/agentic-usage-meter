import { describe, expect, it } from "vitest";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import {
  decodeGitHubCopilotUsage,
  githubAccessTokenRequest,
  githubDeviceAuthorizationRequest,
  GitHubCopilotOAuthFlow,
  GITHUB_COPILOT_CLIENT_ID,
} from "../src/core/providers/github.js";
import { isProviderClientError } from "../src/core/errors.js";
import { HTTPResponse, type HTTPTransport } from "../src/core/http.js";

const fixture = (name: string): Uint8Array =>
  new Uint8Array(readFileSync(join(__dirname, "fixtures", name)));

const ACCOUNT = "10000000-0000-0000-0000-0000000000dd";
const FETCHED = new Date("2026-07-15T12:00:00Z");

describe("decodeGitHubCopilotUsage", () => {
  it("decodes the fixture: limited quotas become monthly windows", () => {
    const result = decodeGitHubCopilotUsage(fixture("github-copilot-usage.json"), ACCOUNT, FETCHED);

    expect(result.plan).toBe("individual_pro");
    expect(result.userID).toBe("42"); // numeric 42 coerced to string

    // "chat" is unlimited and skipped. July has 31 days → 2678400s duration.
    expect(result.snapshot.windows).toHaveLength(2);
    const [completions, premium] = result.snapshot.windows;
    expect(completions).toMatchObject({
      id: "github-copilot-completions",
      kind: "monthly",
      duration: 2_678_400,
      resetAt: "2026-08-01T00:00:00.000Z",
      consumedFraction: 0.25, // (1000 - 750) / 1000
      label: "Completions",
    });
    expect(premium).toMatchObject({
      id: "github-copilot-premium-interactions",
      consumedFraction: 0.6, // (300 - 120) / 300
      label: "Premium interactions",
    });
  });

  it("returns no windows when every quota is unlimited", () => {
    const payload = JSON.stringify({
      quota_snapshots: { chat: { unlimited: true } },
    });
    const result = decodeGitHubCopilotUsage(new TextEncoder().encode(payload), ACCOUNT, FETCHED);
    expect(result.snapshot.windows).toEqual([]);
  });

  it("accepts a date-only reset value", () => {
    const payload = JSON.stringify({
      quota_reset_date_utc: "2026-08-01",
      quota_snapshots: { completions: { entitlement: 100, remaining: 40 } },
    });
    const result = decodeGitHubCopilotUsage(new TextEncoder().encode(payload), ACCOUNT, FETCHED);
    expect(result.snapshot.windows[0]!.resetAt).toBe("2026-08-01T00:00:00.000Z");
  });

  it("rejects limited quotas without a reset date", () => {
    const payload = JSON.stringify({
      quota_snapshots: { completions: { entitlement: 100, remaining: 40 } },
    });
    try {
      decodeGitHubCopilotUsage(new TextEncoder().encode(payload), ACCOUNT, FETCHED);
      expect.unreachable();
    } catch (error) {
      expect(isProviderClientError(error, "unsupportedResponse")).toBe(true);
    }
  });
});

describe("github device OAuth requests", () => {
  it("posts client_id to the device endpoint", () => {
    const request = githubDeviceAuthorizationRequest();
    expect(request.url).toBe("https://github.com/login/device/code");
    expect(request.headers["Accept"]).toBe("application/json");
    expect(new URLSearchParams(request.body).get("client_id")).toBe(GITHUB_COPILOT_CLIENT_ID);
  });

  it("posts the device-code grant to the token endpoint", () => {
    const request = githubAccessTokenRequest("device-code");
    expect(request.url).toBe("https://github.com/login/oauth/access_token");
    const body = new URLSearchParams(request.body);
    expect(body.get("device_code")).toBe("device-code");
    expect(body.get("grant_type")).toBe("urn:ietf:params:oauth:grant-type:device_code");
  });
});

describe("GitHubCopilotOAuthFlow", () => {
  const jsonResponse = (status: number, body: unknown) =>
    new HTTPResponse(new TextEncoder().encode(JSON.stringify(body)), status, {});
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

  it("polls, then resolves identity via api.github.com/user", async () => {
    const transport = queueTransport([
      jsonResponse(200, {
        device_code: "dc",
        user_code: "1111-2222",
        verification_uri: "https://github.com/login/device",
        expires_in: 900,
        interval: 1,
      }),
      jsonResponse(200, { error: "authorization_pending" }),
      jsonResponse(200, { access_token: "gho_token" }),
      jsonResponse(200, { login: "octocat", id: 1234 }),
    ]);
    let prompted: string | null = null;
    const flow = new GitHubCopilotOAuthFlow(
      transport,
      async () => true,
      () => FETCHED,
      async () => {},
    );
    const credential = await flow.authenticate((prompt) => {
      prompted = prompt.userCode;
    });
    expect(prompted).toBe("1111-2222");
    expect(credential).toEqual({
      accessToken: "gho_token",
      userID: "1234",
      login: "octocat",
    });
  });

  it("fails on access_denied", async () => {
    const transport = queueTransport([
      jsonResponse(200, {
        device_code: "dc",
        user_code: "1111-2222",
        verification_uri: "https://github.com/login/device",
        expires_in: 900,
        interval: 1,
      }),
      jsonResponse(200, { error: "access_denied" }),
    ]);
    const flow = new GitHubCopilotOAuthFlow(transport, async () => true, () => FETCHED, async () => {});
    await expect(flow.authenticate()).rejects.toSatisfy((error) =>
      isProviderClientError(error, "reauthenticationRequired"),
    );
  });
});
