// OpenCode providers (Go + Zen) — port of OpenCodeUsageAdapters.swift,
// OpenCodeGoUsageDecoder.swift, OpenCodeZenUsageDecoder.swift,
// OpenCodeDashboardHTML.swift and OpenCodeLoginSession.swift's detector.

import {
  makeAvailableBalance,
  makeUsageWindow,
  type UsageSnapshot,
  type UsageWindow,
  type UsageWindowKind,
} from "../models.js";
import { ProviderClientError } from "../errors.js";
import { monthIntervalUTC, oneMonthBeforeUTC, parseISO8601 } from "../dates.js";
import type { HTTPTransport } from "../http.js";
import type { SessionCookie } from "./claude.js";

// ---------------------------------------------------------------------------
// HTML helpers (OpenCodeDashboardHTML port)
// ---------------------------------------------------------------------------

export function normalizeDashboardHTML(data: Uint8Array): string {
  let text: string;
  try {
    text = new TextDecoder("utf-8", { fatal: true }).decode(data);
  } catch {
    throw ProviderClientError.unsupportedResponse();
  }
  const replacements: [string, string][] = [
    ["&quot;", '"'],
    ["&#34;", '"'],
    ["&#x27;", "'"],
    ["&#39;", "'"],
    ["&amp;", "&"],
    ['\\"', '"'],
    ["\\u0022", '"'],
  ];
  for (const [encoded, decoded] of replacements) {
    text = text.split(encoded).join(decoded);
  }
  return text;
}

function escapeRegExp(value: string): string {
  return value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

export function htmlObjectBody(fieldName: string, text: string): string | null {
  const pattern = new RegExp(
    `["']?${escapeRegExp(fieldName)}["']?\\s*:\\s*(?:\\$R\\[\\d+\\]\\s*=\\s*)?\\{(?<body>[^{}]*)\\}`,
    "s",
  );
  const match = pattern.exec(text);
  return match?.groups?.["body"] ?? null;
}

export function htmlNumber(fieldName: string, text: string): number | null {
  const pattern = new RegExp(
    `["']?${escapeRegExp(fieldName)}["']?\\s*:\\s*"?(-?\\d+(?:\\.\\d+)?)"?`,
  );
  const match = pattern.exec(text);
  if (!match) return null;
  const value = Number(match[1]);
  return Number.isFinite(value) ? value : null;
}

export function htmlString(fieldName: string, text: string): string | null {
  const pattern = new RegExp(
    `["']?${escapeRegExp(fieldName)}["']?\\s*:\\s*["']([^"']+)["']`,
  );
  const match = pattern.exec(text);
  return match?.[1] ?? null;
}

export function htmlDate(fieldName: string, text: string): Date | null {
  const value = htmlString(fieldName, text);
  return value ? parseISO8601(value) : null;
}

// ---------------------------------------------------------------------------
// Login detection (OpenCodeLoginDetector port)
// ---------------------------------------------------------------------------

export function isOpenCodeDomain(domain: string): boolean {
  const cleaned = domain.toLowerCase().replace(/^\.+|\.+$/g, "");
  return cleaned === "opencode.ai" || cleaned.endsWith(".opencode.ai");
}

export function openCodeWorkspaceID(urlString: string): string | null {
  let url: URL;
  try {
    url = new URL(urlString);
  } catch {
    return null;
  }
  if (!isOpenCodeDomain(url.host)) return null;
  const components = url.pathname.split("/").filter((part) => part !== "");
  if (components.length < 2 || components[0] !== "workspace") return null;
  const workspaceID = decodeURIComponent(components[1]!).trim();
  return workspaceID === "" ? null : workspaceID;
}

export function openCodeAuthCookie(cookies: SessionCookie[]): string | null {
  const cookie = cookies.find(
    (entry) => entry.name === "auth" && entry.value !== "" && isOpenCodeDomain(entry.domain),
  );
  return cookie?.value ?? null;
}

// ---------------------------------------------------------------------------
// OpenCode Go decoder
// ---------------------------------------------------------------------------

interface WindowCandidate {
  id: string;
  kind: UsageWindowKind;
  duration: number | null;
  resetAt: Date;
  usedPercent: number;
}

interface WindowDefinition {
  field: string;
  label: string;
  id: string;
  kind: UsageWindowKind;
  duration: number | null;
}

const GO_DEFINITIONS: WindowDefinition[] = [
  { field: "rollingUsage", label: "rolling", id: "opencode-go-rolling", kind: "short", duration: 5 * 60 * 60 },
  { field: "weeklyUsage", label: "weekly", id: "opencode-go-weekly", kind: "weekly", duration: 7 * 24 * 60 * 60 },
  { field: "monthlyUsage", label: "monthly", id: "opencode-go-monthly", kind: "monthly", duration: null },
];

function goCandidateFromField(
  definition: WindowDefinition,
  html: string,
  fetchedAt: Date,
): WindowCandidate | null {
  const body = htmlObjectBody(definition.field, html);
  if (!body) return null;
  const usedPercent = htmlNumber("usagePercent", body);
  if (usedPercent === null || usedPercent < 0 || usedPercent > 100) return null;
  const resetSeconds = htmlNumber("resetInSec", body);
  if (resetSeconds === null || !Number.isFinite(resetSeconds) || resetSeconds < 0) {
    return null;
  }
  return {
    id: definition.id,
    kind: definition.kind,
    duration: definition.duration,
    resetAt: new Date(fetchedAt.getTime() + Math.round(resetSeconds) * 1000),
    usedPercent,
  };
}

function dataSlotValue(slotName: string, html: string): string | null {
  const pattern = new RegExp(
    `<[^>]*data-slot\\s*=\\s*["']${escapeRegExp(slotName)}["'][^>]*>(?<value>[\\s\\S]*?)</[^>]+>`,
    "i",
  );
  const match = pattern.exec(html);
  const value = match?.groups?.["value"];
  if (value === undefined) return null;
  return value
    .replace(/<!--[\s\S]*?-->/g, "")
    .replace(/<[^>]+>/g, "")
    .split(/\s+/)
    .filter((part) => part !== "")
    .join(" ");
}

function firstNumber(text: string): number | null {
  const match = /-?\d+(?:\.\d+)?/.exec(text);
  if (!match) return null;
  const value = Number(match[0]);
  return Number.isFinite(value) ? value : null;
}

function durationSeconds(text: string): number | null {
  const pattern = /(\d+(?:\.\d+)?)\s*(day|hour|minute|second)s?/gi;
  let total = 0;
  let found = false;
  for (const match of text.matchAll(pattern)) {
    const value = Number(match[1]);
    if (!Number.isFinite(value)) continue;
    found = true;
    const unit = match[2]!.toLowerCase();
    const multiplier =
      unit === "day" ? 86_400 : unit === "hour" ? 3_600 : unit === "minute" ? 60 : 1;
    total += value * multiplier;
  }
  return found ? total : null;
}

function dataSlotResetSeconds(item: string): number | null {
  if (dataSlotValue("reset-now", item) !== null) return 0;
  const reset = dataSlotValue("reset-time", item);
  if (reset === null) return null;
  return durationSeconds(reset);
}

function dataSlotCandidates(html: string, fetchedAt: Date): WindowCandidate[] {
  const itemPattern = /data-slot\s*=\s*["']usage-item["']/gi;
  const matches = [...html.matchAll(itemPattern)];
  const items = matches.map((match, index) => {
    const start = match.index;
    const end = index + 1 < matches.length ? matches[index + 1]!.index : html.length;
    return html.slice(start, end);
  });
  const candidates: WindowCandidate[] = [];
  for (const item of items) {
    const label = dataSlotValue("usage-label", item)?.toLowerCase();
    if (!label) continue;
    const definition = GO_DEFINITIONS.find((entry) => label.includes(entry.label));
    if (!definition) continue;
    const valueText = dataSlotValue("usage-value", item);
    if (valueText === null) continue;
    const usedPercent = firstNumber(valueText);
    if (usedPercent === null || usedPercent < 0 || usedPercent > 100) continue;
    const resetSeconds = dataSlotResetSeconds(item);
    if (resetSeconds === null) continue;
    candidates.push({
      id: definition.id,
      kind: definition.kind,
      duration: definition.duration,
      resetAt: new Date(fetchedAt.getTime() + resetSeconds * 1000),
      usedPercent,
    });
  }
  return candidates;
}

function monthDurationEndingAt(resetAt: Date): number | null {
  const startAt = oneMonthBeforeUTC(resetAt);
  const duration = (resetAt.getTime() - startAt.getTime()) / 1000;
  return duration > 0 ? duration : null;
}

function goRequiresSubscription(html: string): boolean {
  return (
    /["']?subscriptionPlan["']?\s*:\s*null/i.test(html) &&
    /data-slot\s*=\s*["']subscribe-button["']/i.test(html)
  );
}

export function decodeOpenCodeGoUsage(
  data: Uint8Array,
  accountID: string,
  fetchedAt: Date,
): UsageSnapshot {
  const html = normalizeDashboardHTML(data);
  const solidCandidates = GO_DEFINITIONS.map((definition) =>
    goCandidateFromField(definition, html, fetchedAt),
  ).filter((candidate): candidate is WindowCandidate => candidate !== null);
  const candidates =
    solidCandidates.length > 0 ? solidCandidates : dataSlotCandidates(html, fetchedAt);

  const windows: UsageWindow[] = [];
  for (const candidate of candidates) {
    const duration = candidate.duration ?? monthDurationEndingAt(candidate.resetAt);
    if (duration === null) {
      throw ProviderClientError.unsupportedResponse();
    }
    const window = makeUsageWindow({
      id: candidate.id,
      kind: candidate.kind,
      duration,
      resetAt: candidate.resetAt,
      consumedFraction: candidate.usedPercent / 100,
    });
    if (!window) throw ProviderClientError.unsupportedResponse();
    windows.push(window);
  }

  if (candidates.length === 0 && goRequiresSubscription(html)) {
    throw ProviderClientError.subscriptionRequired();
  }
  if (windows.length !== candidates.length || windows.length === 0) {
    throw ProviderClientError.unsupportedResponse();
  }
  return {
    accountID,
    fetchedAt: fetchedAt.toISOString(),
    windows,
    balances: [],
  };
}

// ---------------------------------------------------------------------------
// OpenCode Zen decoder
// ---------------------------------------------------------------------------

export function decodeOpenCodeZenUsage(
  data: Uint8Array,
  accountID: string,
  fetchedAt: Date,
): UsageSnapshot {
  const html = normalizeDashboardHTML(data);
  const balanceInMicrocents = htmlNumber("balance", html);
  if (balanceInMicrocents === null) {
    throw ProviderClientError.unsupportedResponse();
  }
  const balance = makeAvailableBalance({
    id: "opencode-zen-balance",
    label: "Zen balance",
    remainingAmount: balanceInMicrocents / 100_000_000,
    unit: "USD",
  });
  if (!balance) throw ProviderClientError.unsupportedResponse();

  const windows: UsageWindow[] = [];
  const monthlyLimit = htmlNumber("monthlyLimit", html);
  if (monthlyLimit !== null && monthlyLimit > 0) {
    const cycle = monthIntervalUTC(fetchedAt);
    const reportedUsage = htmlNumber("monthlyUsage", html) ?? 0;
    const updatedAt = htmlDate("timeMonthlyUsageUpdated", html);
    const inCycle =
      updatedAt !== null && updatedAt >= cycle.start && updatedAt < cycle.end;
    // Port of `updatedAt.map { cycle.range.contains($0) } == false ? 0 : ...`:
    // a stale update timestamp zeroes usage; a missing timestamp trusts the
    // reported value.
    const usageInMicrocents =
      updatedAt !== null && !inCycle ? 0 : Math.max(0, reportedUsage);
    const monthly = makeUsageWindow({
      id: "opencode-zen-monthly",
      kind: "monthly",
      duration: (cycle.end.getTime() - cycle.start.getTime()) / 1000,
      resetAt: cycle.end,
      consumedFraction: Math.min(usageInMicrocents / 100_000_000 / monthlyLimit, 1),
    });
    if (!monthly) throw ProviderClientError.unsupportedResponse();
    windows.push(monthly);
  }

  return {
    accountID,
    fetchedAt: fetchedAt.toISOString(),
    windows,
    balances: [balance],
  };
}

// ---------------------------------------------------------------------------
// Shared dashboard usage client
// ---------------------------------------------------------------------------

export class OpenCodeDashboardUsageClient {
  constructor(
    private readonly page: "go" | "billing",
    private readonly decode: (
      data: Uint8Array,
      accountID: string,
      fetchedAt: Date,
    ) => UsageSnapshot,
    private readonly transport: HTTPTransport,
  ) {}

  async fetchUsage(
    accountID: string,
    credential: { workspaceID: string; authCookie: string },
    now: Date,
  ): Promise<UsageSnapshot> {
    const workspaceID = credential.workspaceID.trim();
    if (!workspaceID || !credential.authCookie) {
      throw ProviderClientError.reauthenticationRequired();
    }
    const cookieHeaderValue = credential.authCookie.includes("auth=")
      ? credential.authCookie
      : `auth=${credential.authCookie}`;
    const response = await this.transport.send({
      url: `https://opencode.ai/workspace/${encodeURIComponent(workspaceID)}/${this.page}`,
      method: "GET",
      headers: {
        Accept: "text/html,application/xhtml+xml",
        Cookie: cookieHeaderValue,
      },
    });
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return this.decode(response.data, accountID, now);
    }
    if (
      (response.statusCode >= 300 && response.statusCode < 400) ||
      response.statusCode === 401 ||
      response.statusCode === 403
    ) {
      throw ProviderClientError.reauthenticationRequired();
    }
    if (response.statusCode === 429) {
      throw ProviderClientError.retryAfter(response.retryDate(now));
    }
    throw ProviderClientError.temporaryFailure();
  }
}
