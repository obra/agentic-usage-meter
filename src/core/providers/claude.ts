// Claude provider — port of ClaudeUsageClient.swift, ClaudeUsageDecoder.swift
// and the cookie handling from ClaudeWebUsageClient.swift /
// ClaudeLoginCookieDetector.swift.

import {
  makeUsageBalance,
  makeUsageWindow,
  type UsageBalance,
  type UsageSnapshot,
  type UsageWindow,
} from "../models.js";
import { ProviderClientError } from "../errors.js";
import { hexOfUTF8, parseISO8601 } from "../dates.js";
import type { HTTPTransport } from "../http.js";

// ---------------------------------------------------------------------------
// Decoder
// ---------------------------------------------------------------------------

interface WindowPayload {
  utilization: number;
  resets_at?: string | null;
}

interface ClaudeUsagePayload {
  five_hour: WindowPayload;
  seven_day: WindowPayload;
  extra_usage?: { is_enabled?: boolean; user_disabled?: boolean } | null;
  spend?: {
    enabled?: boolean;
    balance?: { amount_minor: number; currency: string; exponent: number } | null;
  } | null;
  limits?: unknown;
}

interface LimitPayload {
  group?: unknown;
  percent?: unknown;
  resets_at?: unknown;
  scope?: { model?: { id?: unknown; display_name?: unknown } | null } | null;
}

function isValidUtilization(value: number): boolean {
  return Number.isFinite(value) && value >= 0 && value <= 100;
}

function normalizedWindow(
  payload: WindowPayload,
  id: string,
  kind: "short" | "weekly",
  duration: number,
): UsageWindow | null {
  if (typeof payload.utilization !== "number" || !isValidUtilization(payload.utilization)) {
    return null;
  }
  const resetAt = payload.resets_at ? parseISO8601(payload.resets_at) : null;
  if (payload.resets_at && !resetAt) return null;
  return makeUsageWindow({
    id,
    kind,
    duration,
    resetAt,
    consumedFraction: payload.utilization / 100,
  });
}

function normalizedText(value: unknown): string | undefined {
  if (typeof value !== "string") return undefined;
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : undefined;
}

function shouldPrefer(candidate: UsageWindow, existing: UsageWindow): boolean {
  if (candidate.consumedFraction !== existing.consumedFraction) {
    return candidate.consumedFraction > existing.consumedFraction;
  }
  if (candidate.resetAt && !existing.resetAt) return true;
  if (!candidate.resetAt && existing.resetAt) return false;
  if (candidate.resetAt && existing.resetAt) {
    return candidate.resetAt < existing.resetAt;
  }
  return false;
}

// Port of ClaudeUsageDecoder.scopedWindows(from:). Scoped limits are optional
// surface: unusable entries are skipped, never a reason to reject.
function scopedWindows(limits: unknown): { windows: UsageWindow[]; malformed: number } {
  if (!Array.isArray(limits)) return { windows: [], malformed: 0 };
  const windows: UsageWindow[] = [];
  const indexByID = new Map<string, number>();
  let malformed = 0;

  for (const rawEntry of limits) {
    const entry = rawEntry as LimitPayload | null;
    if (entry === null || typeof entry !== "object") {
      malformed += 1;
      continue;
    }
    if (entry.group !== "weekly") continue;
    if (!entry.scope || typeof entry.scope !== "object") continue;
    const model = entry.scope.model;
    if (!model || typeof model !== "object") {
      malformed += 1;
      continue;
    }
    const displayName = normalizedText(model.display_name);
    const modelID = normalizedText(model.id);
    const identity = modelID ? `id:${modelID}` : displayName ? `name:${displayName}` : undefined;
    const label = displayName ?? modelID;
    if (!identity || !label) {
      malformed += 1;
      continue;
    }
    const percent = typeof entry.percent === "number" ? entry.percent : NaN;
    if (!isValidUtilization(percent)) {
      malformed += 1;
      continue;
    }
    const resetAt =
      typeof entry.resets_at === "string" ? parseISO8601(entry.resets_at) : null;
    const window = makeUsageWindow({
      id: `claude-weekly-scoped-${hexOfUTF8(identity)}`,
      kind: "weekly",
      duration: 604_800,
      resetAt,
      consumedFraction: percent / 100,
      label,
    });
    if (!window) {
      malformed += 1;
      continue;
    }
    const existing = indexByID.get(window.id);
    if (existing !== undefined) {
      if (shouldPrefer(window, windows[existing]!)) {
        windows[existing] = window;
      }
    } else {
      indexByID.set(window.id, windows.length);
      windows.push(window);
    }
  }
  return { windows, malformed };
}

function normalizedBalances(payload: ClaudeUsagePayload): UsageBalance[] {
  const extraUsage = payload.extra_usage ?? undefined;
  const spend = payload.spend ?? undefined;
  if (
    extraUsage?.is_enabled === false ||
    extraUsage?.user_disabled === true ||
    spend?.enabled === false
  ) {
    const disabled = makeUsageBalance({
      id: "claude-usage-credits",
      label: "Usage credits",
      value: { state: "disabled" },
    });
    if (!disabled) throw ProviderClientError.unsupportedResponse();
    return [disabled];
  }

  const money = spend?.balance ?? undefined;
  if (!money) return [];
  const currency = typeof money.currency === "string" ? money.currency.trim() : "";
  const amountMinor = typeof money.amount_minor === "number" ? money.amount_minor : NaN;
  const exponent = typeof money.exponent === "number" ? money.exponent : -1;
  if (!(amountMinor >= 0) || !(exponent >= 0 && exponent <= 18) || !currency) {
    throw ProviderClientError.unsupportedResponse();
  }
  const amount = amountMinor / 10 ** exponent;
  const balance = makeUsageBalance({
    id: "claude-usage-credits",
    label: "Usage credits",
    value: { state: "available", amount, unit: currency },
  });
  if (!balance) throw ProviderClientError.unsupportedResponse();
  return [balance];
}

export function decodeClaudeUsage(
  data: Uint8Array,
  accountID: string,
  fetchedAt: Date,
): UsageSnapshot {
  let payload: ClaudeUsagePayload;
  try {
    payload = JSON.parse(new TextDecoder().decode(data)) as ClaudeUsagePayload;
    if (typeof payload !== "object" || payload === null) throw new Error("not an object");
    if (typeof payload.five_hour?.utilization !== "number") throw new Error("five_hour");
    if (typeof payload.seven_day?.utilization !== "number") throw new Error("seven_day");
  } catch {
    throw ProviderClientError.unsupportedResponse();
  }

  const shortWindow = normalizedWindow(payload.five_hour, "five-hour", "short", 18_000);
  const weeklyWindow = normalizedWindow(payload.seven_day, "seven-day", "weekly", 604_800);
  if (!shortWindow || !weeklyWindow) {
    throw ProviderClientError.unsupportedResponse();
  }

  const scoped = scopedWindows(payload.limits ?? undefined);
  return {
    accountID,
    fetchedAt: fetchedAt.toISOString(),
    windows: [shortWindow, weeklyWindow, ...scoped.windows],
    balances: normalizedBalances(payload),
  };
}

// ---------------------------------------------------------------------------
// OAuth setup-token client (api.anthropic.com/api/oauth/usage)
// ---------------------------------------------------------------------------

export class ClaudeUsageClient {
  constructor(private readonly transport: HTTPTransport) {}

  async fetchUsage(
    accountID: string,
    token: string,
    now: Date,
  ): Promise<UsageSnapshot> {
    if (!token) throw ProviderClientError.credentialMismatch();
    const response = await this.transport.send({
      url: "https://api.anthropic.com/api/oauth/usage",
      method: "GET",
      headers: {
        Authorization: `Bearer ${token}`,
        "anthropic-beta": "oauth-2025-04-20",
      },
    });
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return decodeClaudeUsage(response.data, accountID, now);
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
// Web-session client (claude.ai cookies)
// ---------------------------------------------------------------------------

export const CLAUDE_BASE_URL = "https://claude.ai";
export const CLAUDE_WEB_USER_AGENT =
  "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15";

export interface SessionCookie {
  name: string;
  value: string;
  domain: string;
  expirationDate?: number; // seconds since epoch
}

export function isClaudeDomain(domain: string): boolean {
  const cleaned = domain.toLowerCase().replace(/^\.+|\.+$/g, "");
  return cleaned === "claude.ai" || cleaned.endsWith(".claude.ai");
}

// Port of ClaudeLoginCookieDetector: sessionKey is required; cf_clearance
// and __cf_bm ride along when present.
export function claudeAPICookies(cookies: SessionCookie[]): SessionCookie[] | null {
  const allowed = new Set(["sessionKey", "cf_clearance", "__cf_bm"]);
  const selected = cookies.filter(
    (cookie) => allowed.has(cookie.name) && cookie.value !== "" && isClaudeDomain(cookie.domain),
  );
  if (!selected.some((cookie) => cookie.name === "sessionKey")) return null;
  return selected;
}

export function cookieHeader(cookies: SessionCookie[]): string {
  return cookies.map((cookie) => `${cookie.name}=${cookie.value}`).join("; ");
}

export interface ClaudeOrganization {
  uuid: string;
  name: string;
  capabilities: string[];
}

export function decodeClaudeOrganizations(data: Uint8Array): ClaudeOrganization[] {
  let parsed: unknown;
  try {
    parsed = JSON.parse(new TextDecoder().decode(data));
  } catch {
    throw ProviderClientError.unsupportedResponse();
  }
  if (!Array.isArray(parsed)) throw ProviderClientError.unsupportedResponse();
  const organizations: ClaudeOrganization[] = [];
  for (const entry of parsed) {
    const candidate = entry as { uuid?: unknown; name?: unknown; capabilities?: unknown };
    if (typeof candidate?.uuid !== "string" || typeof candidate?.name !== "string") {
      throw ProviderClientError.unsupportedResponse();
    }
    organizations.push({
      uuid: candidate.uuid,
      name: candidate.name,
      capabilities: Array.isArray(candidate.capabilities)
        ? candidate.capabilities.filter((item): item is string => typeof item === "string")
        : [],
    });
  }
  if (organizations.length === 0) throw ProviderClientError.unsupportedResponse();
  return organizations;
}

export class ClaudeWebUsageClient {
  constructor(private readonly transport: HTTPTransport) {}

  private async send(url: string, cookies: SessionCookie[], now: Date) {
    const response = await this.transport.send({
      url,
      method: "GET",
      headers: {
        Cookie: cookieHeader(cookies),
        Accept: "application/json",
        "User-Agent": CLAUDE_WEB_USER_AGENT,
        Origin: CLAUDE_BASE_URL,
        Referer: CLAUDE_BASE_URL,
      },
    });
    if (response.statusCode >= 200 && response.statusCode < 300) return response;
    if (response.statusCode === 401 || response.statusCode === 403) {
      throw ProviderClientError.reauthenticationRequired();
    }
    if (response.statusCode === 429) {
      throw ProviderClientError.retryAfter(response.retryDate(now));
    }
    throw ProviderClientError.temporaryFailure();
  }

  async organizations(cookies: SessionCookie[]): Promise<ClaudeOrganization[]> {
    const response = await this.send(
      `${CLAUDE_BASE_URL}/api/organizations`,
      cookies,
      new Date(),
    );
    return decodeClaudeOrganizations(response.data);
  }

  async fetchUsage(
    accountID: string,
    organizationID: string,
    cookies: SessionCookie[],
    now: Date,
  ): Promise<UsageSnapshot> {
    const response = await this.send(
      `${CLAUDE_BASE_URL}/api/organizations/${organizationID.toLowerCase()}/usage`,
      cookies,
      now,
    );
    return decodeClaudeUsage(response.data, accountID, now);
  }
}
