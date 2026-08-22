import { describe, expect, it } from "vitest";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import {
  decodeKimiUsage,
  kimiDeviceAuthorizationRequest,
  kimiRefreshRequest,
  KimiOAuthFlow,
  KIMI_CLIENT_ID,
  type KimiDeviceInfo,
} from "../src/core/providers/kimi.js";
import { isProviderClientError, ProviderClientError } from "../src/core/errors.js";
import { HTTPResponse, type HTTPTransport } from "../src/core/http.js";

const fixture = (name: string): Uint8Array =>
  new Uint8Array(readFileSync(join(__dirname, "fixtures", name)));

const ACCOUNT = "10000000-0000-0000-0000-0000000000cc";
const FETCHED = new Date("2026-07-29T18:00:00Z");

describe("decodeKimiUsage", () => {
  it("decodes the fixture: limits entry → short, usage summary → weekly", () => {
    const snapshot = decodeKimiUsage(fixture("kimi-usage.json"), ACCOUNT, FETCHED);
    expect(snapshot.windows).toHaveLength(2);

    const [short, weekly] = snapshot.windows;
    // 300 minutes = 18000s → short; remaining 60 of 100 → 40% consumed;
    // resetIn 3600 relative to fetchedAt.
    expect(short).toMatchObject({
      id: "kimi-short",
      kind: "short",
      duration: 18_000,
      consumedFraction: 0.4,
      resetAt: new Date(FETCHED.getTime() + 3_600_000).toISOString(),
    });
    // usage fallback: 250 of 1000 → 25% weekly with the reported reset time.
    expect(weekly).toMatchObject({
      id: "kimi-weekly",
      kind: "weekly",
      duration: 604_800,
      consumedFraction: 0.25,
      resetAt: "2033-05-18T03:33:20.000Z",
    });
  });

  it("prefers a weekly limits entry over the usage summary", () => {
    const payload = JSON.stringify({
      usage: { limit: 1000, used: 250, resetAt: "2033-05-18T03:33:20Z" },
      limits: [
        {
          window: { duration: 7, timeUnit: "TIME_UNIT_DAY" },
          detail: { limit: 200, used: 50, reset_in: 86_400 },
        },
      ],
    });
    const snapshot = decodeKimiUsage(new TextEncoder().encode(payload), ACCOUNT, FETCHED);
    expect(snapshot.windows).toHaveLength(1);
    expect(snapshot.windows[0]).toMatchObject({
      id: "kimi-weekly",
      consumedFraction: 0.25,
      resetAt: new Date(FETCHED.getTime() + 86_400_000).toISOString(),
    });
  });

  it("parses fractional reset timestamps beyond millisecond precision", () => {
    const payload = JSON.stringify({
      limits: [
        {
          window: { duration: 5, timeUnit: "HOURS" },
          detail: {
            limit: 10,
            used: 1,
            reset_at: "2026-07-29T23:00:00.123456789Z",
          },
        },
      ],
    });
    const snapshot = decodeKimiUsage(new TextEncoder().encode(payload), ACCOUNT, FETCHED);
    // Fractional part truncated to 6 digits: .123457 rounded to ms
    expect(snapshot.windows[0]!.resetAt).toBe("2026-07-29T23:00:00.123Z");
  });

  it("accepts numbers encoded as strings", () => {
    const payload = JSON.stringify({
      usage: { limit: "1000", used: "250", resetIn: "3600" },
    });
    const snapshot = decodeKimiUsage(new TextEncoder().encode(payload), ACCOUNT, FETCHED);
    expect(snapshot.windows[0]).toMatchObject({
      kind: "weekly",
      consumedFraction: 0.25,
    });
  });

  it("rejects when nothing decodes", () => {
    try {
      decodeKimiUsage(new TextEncoder().encode("{}"), ACCOUNT, FETCHED);
      expect.unreachable();
    } catch (error) {
      expect(isProviderClientError(error, "unsupportedResponse")).toBe(true);
    }
  });
});

describe("kimi OAuth requests", () => {
  const device: KimiDeviceInfo = {
    name: "Desk Ω", // non-ASCII must be sanitized
    model: "windows-x64",
    osVersion: "10.0.22631",
    id: "device-id",
    clientVersion: "0.1.0",
  };

  it("posts the device authorization form with ASCII-safe headers", () => {
    const request = kimiDeviceAuthorizationRequest(device);
    expect(request.url).toBe("https://auth.kimi.com/api/oauth/device_authorization");
    expect(request.headers["Content-Type"]).toBe("application/x-www-form-urlencoded");
    expect(request.headers["X-Msh-Platform"]).toBe("kimi_cli");
    expect(request.headers["X-Msh-Version"]).toBe("0.1.0");
    expect(request.headers["X-Msh-Device-Name"]).toBe("Desk");
    expect(request.headers["X-Msh-Device-Model"]).toBe("windows-x64");
    expect(request.headers["X-Msh-Os-Version"]).toBe("10.0.22631");
    expect(request.headers["X-Msh-Device-Id"]).toBe("device-id");
    expect(new URLSearchParams(request.body).get("client_id")).toBe(KIMI_CLIENT_ID);
  });

  it("posts the refresh form", () => {
    const request = kimiRefreshRequest("refresh-token", device);
    const body = new URLSearchParams(request.body);
    expect(body.get("grant_type")).toBe("refresh_token");
    expect(body.get("refresh_token")).toBe("refresh-token");
    expect(body.get("client_id")).toBe(KIMI_CLIENT_ID);
  });
});

describe("KimiOAuthFlow", () => {
  const device: KimiDeviceInfo = {
    name: "test",
    model: "test",
    osVersion: "1",
    id: "id",
    clientVersion: "0.1.0",
  };

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

  const jsonResponse = (status: number, body: unknown) =>
    new HTTPResponse(new TextEncoder().encode(JSON.stringify(body)), status, {});

  it("polls through authorization_pending until the token arrives", async () => {
    const transport = queueTransport([
      jsonResponse(200, {
        device_code: "dc",
        user_code: "ABCD-EFGH",
        verification_uri_complete: "https://auth.kimi.com/device?user_code=ABCD-EFGH",
        expires_in: 900,
        interval: 1,
      }),
      jsonResponse(400, { error: "authorization_pending" }),
      jsonResponse(200, { access_token: "at", refresh_token: "rt", expires_in: 3600 }),
    ]);
    let opened: string | null = null;
    let prompted: string | null = null;
    const flow = new KimiOAuthFlow(
      device,
      transport,
      async (url) => {
        opened = url;
        return true;
      },
      () => FETCHED,
      async () => {},
    );
    const credential = await flow.authenticate((prompt) => {
      prompted = prompt.userCode;
    });
    expect(prompted).toBe("ABCD-EFGH");
    expect(opened).toBe("https://auth.kimi.com/device?user_code=ABCD-EFGH");
    expect(credential.accessToken).toBe("at");
    expect(credential.refreshToken).toBe("rt");
    expect(credential.expiresAt).toBe(
      new Date(FETCHED.getTime() + 3_600_000).toISOString(),
    );
  });

  it("rejects a verification URL on an unexpected host", async () => {
    const transport = queueTransport([
      jsonResponse(200, {
        device_code: "dc",
        user_code: "ABCD-EFGH",
        verification_uri_complete: "https://evil.example.com/device",
        expires_in: 900,
        interval: 1,
      }),
    ]);
    const flow = new KimiOAuthFlow(device, transport, async () => true, () => FETCHED, async () => {});
    try {
      await flow.authenticate();
      expect.unreachable();
    } catch (error) {
      expect(isProviderClientError(error, "unsupportedResponse")).toBe(true);
    }
  });

  it("maps refresh failures: 401 → reauthentication, 500 → temporary", async () => {
    const flow401 = new KimiOAuthFlow(
      device,
      queueTransport([jsonResponse(401, {})]),
      async () => true,
      () => FETCHED,
      async () => {},
    );
    await expect(
      flow401.refresh({ accessToken: "a", refreshToken: "r" }),
    ).rejects.toSatisfy((error) => isProviderClientError(error, "reauthenticationRequired"));

    const flow500 = new KimiOAuthFlow(
      device,
      queueTransport([jsonResponse(500, {})]),
      async () => true,
      () => FETCHED,
      async () => {},
    );
    await expect(
      flow500.refresh({ accessToken: "a", refreshToken: "r" }),
    ).rejects.toSatisfy((error) => isProviderClientError(error, "temporaryFailure"));
  });

  it("requires a refresh token", async () => {
    const flow = new KimiOAuthFlow(device, queueTransport([]), async () => true);
    await expect(flow.refresh({ accessToken: "a" })).rejects.toSatisfy((error) =>
      isProviderClientError(error, "reauthenticationRequired"),
    );
    void ProviderClientError;
  });
});
