// MiniMax provider — port of MiniMaxUsageAdapter.swift and
// MiniMaxUsageDecoder.swift. Note the upstream quirk: the field named
// `current_interval_usage_count` is treated as the REMAINING count.

import {
  makeUsageWindow,
  type UsageSnapshot,
  type UsageWindow,
} from "../models.js";
import { ProviderClientError } from "../errors.js";
import { flexibleNumber } from "../dates.js";
import type { HTTPTransport } from "../http.js";

interface Quota {
  total: number;
  consumedFraction: number;
  startsAt: Date | null;
  endsAt: Date;
}

function makeQuota(input: {
  total: unknown;
  remaining: unknown;
  startsAtMilliseconds: unknown;
  endsAtMilliseconds: unknown;
}): Quota | null {
  const total = flexibleNumber(input.total);
  const remaining = flexibleNumber(input.remaining);
  const endsMs = flexibleNumber(input.endsAtMilliseconds);
  if (
    total === undefined ||
    !Number.isFinite(total) ||
    total <= 0 ||
    remaining === undefined ||
    !Number.isFinite(remaining) ||
    endsMs === undefined ||
    !Number.isFinite(endsMs) ||
    endsMs <= 0
  ) {
    return null;
  }
  const startsMs = flexibleNumber(input.startsAtMilliseconds);
  const clampedRemaining = Math.min(Math.max(remaining, 0), total);
  return {
    total,
    consumedFraction: (total - clampedRemaining) / total,
    startsAt:
      startsMs !== undefined && Number.isFinite(startsMs) && startsMs > 0
        ? new Date(startsMs)
        : null,
    endsAt: new Date(endsMs),
  };
}

interface Candidate {
  modelName: string;
  interval: Quota | null;
  weekly: Quota | null;
}

function candidateFromRow(row: Record<string, unknown>): Candidate | null {
  const interval = makeQuota({
    total: row["current_interval_total_count"],
    remaining: row["current_interval_usage_count"],
    startsAtMilliseconds: row["start_time"],
    endsAtMilliseconds: row["end_time"],
  });
  const weekly = makeQuota({
    total: row["current_weekly_total_count"],
    remaining: row["current_weekly_usage_count"],
    startsAtMilliseconds: row["weekly_start_time"],
    endsAtMilliseconds: row["weekly_end_time"],
  });
  if (!interval && !weekly) return null;
  return {
    modelName: typeof row["model_name"] === "string" ? row["model_name"] : "",
    interval,
    weekly,
  };
}

function candidateIsPreferred(lhs: Candidate, rhs: Candidate): number {
  const lhsConsumed = Math.max(
    lhs.interval?.consumedFraction ?? 0,
    lhs.weekly?.consumedFraction ?? 0,
  );
  const rhsConsumed = Math.max(
    rhs.interval?.consumedFraction ?? 0,
    rhs.weekly?.consumedFraction ?? 0,
  );
  if (lhsConsumed !== rhsConsumed) return rhsConsumed - lhsConsumed;
  const lhsCapacity = (lhs.interval?.total ?? 0) + (lhs.weekly?.total ?? 0);
  const rhsCapacity = (rhs.interval?.total ?? 0) + (rhs.weekly?.total ?? 0);
  if (lhsCapacity !== rhsCapacity) return rhsCapacity - lhsCapacity;
  return lhs.modelName < rhs.modelName ? -1 : lhs.modelName > rhs.modelName ? 1 : 0;
}

function quotaToWindow(
  quota: Quota | null,
  id: string,
  kind: "short" | "weekly",
  duration: number,
): UsageWindow | null {
  if (!quota) return null;
  return makeUsageWindow({
    id,
    kind,
    duration,
    resetAt: quota.endsAt,
    consumedFraction: quota.consumedFraction,
    reportedStartAt: quota.startsAt,
  });
}

export function decodeMiniMaxUsage(
  data: Uint8Array,
  accountID: string,
  fetchedAt: Date,
): UsageSnapshot {
  let response: Record<string, unknown>;
  try {
    response = JSON.parse(new TextDecoder().decode(data));
  } catch {
    throw ProviderClientError.unsupportedResponse();
  }

  const baseResponse = (response["base_resp"] ?? {}) as Record<string, unknown>;
  let statusCode: number | undefined;
  if (typeof baseResponse["status_code"] === "number") {
    statusCode = baseResponse["status_code"];
  } else if (typeof baseResponse["status_code"] === "string") {
    const parsed = Number(baseResponse["status_code"]);
    if (Number.isInteger(parsed)) statusCode = parsed;
  }
  if (statusCode !== 0) throw ProviderClientError.unsupportedResponse();

  const rows = Array.isArray(response["model_remains"])
    ? (response["model_remains"] as Record<string, unknown>[])
    : [];
  const candidates = rows
    .map(candidateFromRow)
    .filter((candidate): candidate is Candidate => candidate !== null)
    .sort(candidateIsPreferred);
  const candidate = candidates[0];
  if (!candidate) throw ProviderClientError.unsupportedResponse();

  const windows = [
    quotaToWindow(candidate.interval, "minimax-short", "short", 18_000),
    quotaToWindow(candidate.weekly, "minimax-weekly", "weekly", 604_800),
  ].filter((window): window is UsageWindow => window !== null);
  if (windows.length === 0) throw ProviderClientError.unsupportedResponse();

  return {
    accountID,
    fetchedAt: fetchedAt.toISOString(),
    windows,
    balances: [],
  };
}

export class MiniMaxUsageClient {
  constructor(private readonly transport: HTTPTransport) {}

  async fetchUsage(
    accountID: string,
    apiKey: string,
    now: Date,
  ): Promise<UsageSnapshot> {
    if (!apiKey.trim()) throw ProviderClientError.reauthenticationRequired();
    const response = await this.transport.send({
      url: "https://api.minimax.io/v1/api/openplatform/coding_plan/remains",
      method: "GET",
      headers: { Authorization: `Bearer ${apiKey}` },
    });
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return decodeMiniMaxUsage(response.data, accountID, now);
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
