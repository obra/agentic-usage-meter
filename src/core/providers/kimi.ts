// Kimi provider — port of KimiUsageClient.swift, KimiOAuthRequests.swift and
// KimiOAuthFlow.swift.

import {
  makeUsageWindow,
  type OAuthCredential,
  type UsageSnapshot,
  type UsageWindow,
  type UsageWindowKind,
} from "../models.js";
import { ProviderClientError } from "../errors.js";
import { flexibleNumber, parseKimiResetDate } from "../dates.js";
import { formURLEncoded, type HTTPTransport } from "../http.js";

// ---------------------------------------------------------------------------
// Usage decode
// ---------------------------------------------------------------------------

interface KimiDetail {
  limit?: number | undefined;
  used?: number | undefined;
  remaining?: number | undefined;
  resetAtValue?: string | undefined;
  resetIn?: number | undefined;
}

interface KimiLimitEntry {
  windowDurationSeconds?: number;
  detail: KimiDetail;
}

function windowKindForDuration(duration: number): UsageWindowKind | null {
  if (duration === 18_000) return "short";
  if (duration === 604_800) return "weekly";
  return null;
}

// Port of KimiUsageResponse.Window.durationInSeconds.
function durationInSeconds(duration: unknown, timeUnit: unknown): number | undefined {
  const value = flexibleNumber(duration);
  if (value === undefined || !Number.isFinite(value) || value <= 0) return undefined;
  if (typeof timeUnit !== "string") return undefined;
  const raw = timeUnit.toUpperCase();
  const unit = raw.startsWith("TIME_UNIT_") ? raw.slice("TIME_UNIT_".length) : raw;
  switch (unit) {
    case "MINUTE":
    case "MINUTES":
      return value * 60;
    case "HOUR":
    case "HOURS":
      return value * 3_600;
    case "DAY":
    case "DAYS":
      return value * 86_400;
    case "SECOND":
    case "SECONDS":
      return value;
    default:
      return undefined;
  }
}

// Port of KimiUsageResponse.Detail — tolerant of camelCase, snake_case, and
// alternate field names, with numbers arriving as strings.
function decodeDetail(raw: unknown): KimiDetail {
  const record = (raw ?? {}) as Record<string, unknown>;
  const resetAtValue = [
    record["resetAt"],
    record["reset_at"],
    record["resetTime"],
    record["reset_time"],
  ].find((value): value is string => typeof value === "string");
  const resetIn = [
    flexibleNumber(record["resetIn"]),
    flexibleNumber(record["reset_in"]),
    flexibleNumber(record["ttl"]),
    flexibleNumber(record["window"]),
  ].find((value): value is number => value !== undefined);
  return {
    limit: flexibleNumber(record["limit"]),
    used: flexibleNumber(record["used"]),
    remaining: flexibleNumber(record["remaining"]),
    ...(resetAtValue !== undefined ? { resetAtValue } : {}),
    ...(resetIn !== undefined ? { resetIn } : {}),
  };
}

function detailResetAt(detail: KimiDetail, fetchedAt: Date): Date | null {
  if (detail.resetAtValue) {
    const parsed = parseKimiResetDate(detail.resetAtValue, fetchedAt);
    if (parsed) return parsed;
  }
  if (
    detail.resetIn !== undefined &&
    Number.isFinite(detail.resetIn) &&
    detail.resetIn >= 0
  ) {
    return new Date(fetchedAt.getTime() + detail.resetIn * 1000);
  }
  return null;
}

function makeKimiWindow(
  detail: KimiDetail,
  kind: UsageWindowKind,
  duration: number,
  fetchedAt: Date,
): UsageWindow | null {
  const limit = detail.limit;
  if (limit === undefined || !Number.isFinite(limit) || limit <= 0) return null;
  const used = detail.used ?? (detail.remaining !== undefined ? limit - detail.remaining : undefined);
  if (used === undefined || !Number.isFinite(used) || used < 0 || used > limit) {
    return null;
  }
  const resetAt = detailResetAt(detail, fetchedAt);
  if (!resetAt) return null;
  return makeUsageWindow({
    id: `kimi-${kind}`,
    kind,
    duration,
    resetAt,
    consumedFraction: used / limit,
  });
}

export function decodeKimiUsage(
  data: Uint8Array,
  accountID: string,
  fetchedAt: Date,
): UsageSnapshot {
  let response: { usage?: unknown; limits?: unknown };
  try {
    response = JSON.parse(new TextDecoder().decode(data));
  } catch {
    throw ProviderClientError.unsupportedResponse();
  }

  const windowsByKind = new Map<UsageWindowKind, UsageWindow>();
  const limits = Array.isArray(response.limits) ? response.limits : [];
  for (const rawEntry of limits) {
    const entry = rawEntry as Record<string, unknown>;
    // Entries nest under window/detail, or carry the fields at top level.
    const windowRecord = (entry["window"] ?? entry) as Record<string, unknown>;
    const detailRecord = entry["detail"] ?? entry;
    const seconds = durationInSeconds(windowRecord["duration"], windowRecord["timeUnit"]);
    if (seconds === undefined) continue;
    const kind = windowKindForDuration(seconds);
    if (!kind) continue;
    const window = makeKimiWindow(decodeDetail(detailRecord), kind, seconds, fetchedAt);
    if (!window) throw ProviderClientError.unsupportedResponse();
    windowsByKind.set(kind, window);
  }

  if (!windowsByKind.has("weekly") && response.usage != null) {
    const weekly = makeKimiWindow(decodeDetail(response.usage), "weekly", 604_800, fetchedAt);
    if (!weekly) throw ProviderClientError.unsupportedResponse();
    windowsByKind.set("weekly", weekly);
  }

  const windows = [windowsByKind.get("short"), windowsByKind.get("weekly")].filter(
    (window): window is UsageWindow => window != null,
  );
  if (windows.length === 0) throw ProviderClientError.unsupportedResponse();

  return {
    accountID,
    fetchedAt: fetchedAt.toISOString(),
    windows,
    balances: [],
  };
}

// ---------------------------------------------------------------------------
// Usage client
// ---------------------------------------------------------------------------

export class KimiUsageClient {
  constructor(private readonly transport: HTTPTransport) {}

  async fetchUsage(
    accountID: string,
    oauth: OAuthCredential,
    now: Date,
  ): Promise<UsageSnapshot> {
    if (!oauth.accessToken) throw ProviderClientError.credentialMismatch();
    const response = await this.transport.send({
      url: "https://api.kimi.com/coding/v1/usages",
      method: "GET",
      headers: { Authorization: `Bearer ${oauth.accessToken}` },
    });
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return decodeKimiUsage(response.data, accountID, now);
    }
    if (response.statusCode === 401 || response.statusCode === 403) {
      throw ProviderClientError.reauthenticationRequired();
    }
    if (response.statusCode === 429) {
      throw ProviderClientError.retryAfter(response.retryDate(now));
    }
    throw ProviderClientError.temporaryFailure();
  }
}

// ---------------------------------------------------------------------------
// Device authorization flow
// ---------------------------------------------------------------------------

export const KIMI_CLIENT_ID = "17e5f671-d194-4dfb-9706-5516cb48c098";
const KIMI_DEVICE_AUTHORIZATION_ENDPOINT =
  "https://auth.kimi.com/api/oauth/device_authorization";
const KIMI_TOKEN_ENDPOINT = "https://auth.kimi.com/api/oauth/token";

export interface KimiDeviceInfo {
  name: string;
  model: string;
  osVersion: string;
  id: string;
  clientVersion: string;
}

function asciiHeader(value: string): string {
  const sanitized = Array.from(value)
    .filter((char) => {
      const code = char.codePointAt(0)!;
      return code < 128 && code >= 32 && code !== 127;
    })
    .join("")
    .trim();
  return sanitized.length > 0 ? sanitized : "unknown";
}

function kimiRequest(url: string, form: [string, string][], device: KimiDeviceInfo) {
  return {
    url,
    method: "POST",
    headers: {
      "Content-Type": "application/x-www-form-urlencoded",
      "X-Msh-Platform": "kimi_cli",
      "X-Msh-Version": asciiHeader(device.clientVersion),
      "X-Msh-Device-Name": asciiHeader(device.name),
      "X-Msh-Device-Model": asciiHeader(device.model),
      "X-Msh-Os-Version": asciiHeader(device.osVersion),
      "X-Msh-Device-Id": asciiHeader(device.id),
    },
    body: formURLEncoded(form),
  };
}

export const kimiDeviceAuthorizationRequest = (device: KimiDeviceInfo) =>
  kimiRequest(KIMI_DEVICE_AUTHORIZATION_ENDPOINT, [["client_id", KIMI_CLIENT_ID]], device);

export const kimiDeviceTokenRequest = (deviceCode: string, device: KimiDeviceInfo) =>
  kimiRequest(
    KIMI_TOKEN_ENDPOINT,
    [
      ["client_id", KIMI_CLIENT_ID],
      ["device_code", deviceCode],
      ["grant_type", "urn:ietf:params:oauth:grant-type:device_code"],
    ],
    device,
  );

export const kimiRefreshRequest = (refreshToken: string, device: KimiDeviceInfo) =>
  kimiRequest(
    KIMI_TOKEN_ENDPOINT,
    [
      ["client_id", KIMI_CLIENT_ID],
      ["grant_type", "refresh_token"],
      ["refresh_token", refreshToken],
    ],
    device,
  );

export interface KimiAuthorizationPrompt {
  verificationURL: string;
  userCode: string;
  expiresAt: Date;
}

export type SleepFn = (seconds: number) => Promise<void>;

export class KimiOAuthFlow {
  constructor(
    private readonly device: KimiDeviceInfo,
    private readonly transport: HTTPTransport,
    private readonly openBrowser: (url: string) => Promise<boolean>,
    private readonly now: () => Date = () => new Date(),
    private readonly sleep: SleepFn = (seconds) =>
      new Promise((resolve) => setTimeout(resolve, seconds * 1000)),
  ) {}

  async authenticate(
    onPrompt: (prompt: KimiAuthorizationPrompt) => void = () => {},
  ): Promise<OAuthCredential> {
    const authorizationResponse = await this.transport.send(
      kimiDeviceAuthorizationRequest(this.device),
    );
    if (authorizationResponse.statusCode !== 200) {
      throw ProviderClientError.temporaryFailure();
    }
    let authorization: {
      user_code?: unknown;
      device_code?: unknown;
      verification_uri_complete?: unknown;
      expires_in?: unknown;
      interval?: unknown;
    };
    try {
      authorization = JSON.parse(authorizationResponse.text());
    } catch {
      throw ProviderClientError.unsupportedResponse();
    }
    const deviceCode = authorization.device_code;
    const userCode = authorization.user_code;
    const verificationURLString = authorization.verification_uri_complete;
    if (
      typeof deviceCode !== "string" ||
      deviceCode === "" ||
      typeof userCode !== "string" ||
      userCode === "" ||
      typeof verificationURLString !== "string"
    ) {
      throw ProviderClientError.unsupportedResponse();
    }
    let verificationHost: string;
    try {
      const url = new URL(verificationURLString);
      if (url.protocol !== "https:") throw new Error("scheme");
      verificationHost = url.host;
    } catch {
      throw ProviderClientError.unsupportedResponse();
    }
    if (!["auth.kimi.com", "www.kimi.com"].includes(verificationHost)) {
      throw ProviderClientError.unsupportedResponse();
    }
    const expiresIn =
      typeof authorization.expires_in === "number" && authorization.expires_in > 0
        ? authorization.expires_in
        : 900;
    const intervalValue =
      typeof authorization.interval === "number" ? authorization.interval : 5;

    onPrompt({
      verificationURL: verificationURLString,
      userCode,
      expiresAt: new Date(this.now().getTime() + expiresIn * 1000),
    });
    if (!(await this.openBrowser(verificationURLString))) {
      throw new Error("browser-open-failed");
    }

    let interval = Math.max(intervalValue, 1);
    let remaining = expiresIn;
    while (remaining > 0) {
      const response = await this.transport.send(
        kimiDeviceTokenRequest(deviceCode, this.device),
      );
      if (response.statusCode === 200) {
        return this.decodeCredential(response.data);
      }
      const errorCode = this.tokenErrorCode(response.data);
      if (errorCode === "authorization_pending") {
        // keep polling
      } else if (errorCode === "slow_down") {
        interval += 5;
      } else if (errorCode === "expired_token" || errorCode === "access_denied") {
        throw ProviderClientError.reauthenticationRequired();
      } else if (response.statusCode === 429 || response.statusCode >= 500) {
        // keep polling
      } else {
        throw ProviderClientError.reauthenticationRequired();
      }
      await this.sleep(interval);
      remaining -= interval;
    }
    throw ProviderClientError.reauthenticationRequired();
  }

  async refresh(credential: OAuthCredential): Promise<OAuthCredential> {
    const refreshToken = credential.refreshToken;
    if (!refreshToken) throw ProviderClientError.reauthenticationRequired();
    const response = await this.transport.send(kimiRefreshRequest(refreshToken, this.device));
    if (response.statusCode === 200) {
      return this.decodeCredential(response.data);
    }
    if (response.statusCode === 401 || response.statusCode === 403) {
      throw ProviderClientError.reauthenticationRequired();
    }
    throw ProviderClientError.temporaryFailure();
  }

  private decodeCredential(data: Uint8Array): OAuthCredential {
    let response: { access_token?: unknown; refresh_token?: unknown; expires_in?: unknown };
    try {
      response = JSON.parse(new TextDecoder().decode(data));
    } catch {
      throw ProviderClientError.unsupportedResponse();
    }
    if (
      typeof response.access_token !== "string" ||
      response.access_token === "" ||
      typeof response.refresh_token !== "string" ||
      response.refresh_token === "" ||
      typeof response.expires_in !== "number" ||
      !Number.isFinite(response.expires_in) ||
      response.expires_in <= 0
    ) {
      throw ProviderClientError.unsupportedResponse();
    }
    return {
      accessToken: response.access_token,
      refreshToken: response.refresh_token,
      expiresAt: new Date(this.now().getTime() + response.expires_in * 1000).toISOString(),
    };
  }

  private tokenErrorCode(data: Uint8Array): string | undefined {
    try {
      const parsed = JSON.parse(new TextDecoder().decode(data)) as { error?: unknown };
      return typeof parsed.error === "string" ? parsed.error : undefined;
    } catch {
      return undefined;
    }
  }
}
