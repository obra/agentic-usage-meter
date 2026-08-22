// Z.ai provider — port of ZaiUsageAdapter.swift and ZaiUsageDecoder.swift.

import {
  makeUsageWindow,
  type UsageSnapshot,
  type UsageWindow,
} from "../models.js";
import { ProviderClientError } from "../errors.js";
import type { HTTPTransport } from "../http.js";

interface ZaiLimit {
  type?: unknown;
  unit?: unknown;
  number?: unknown;
  percentage?: unknown;
  nextResetTime?: unknown;
}

function isTokenLimit(limit: ZaiLimit, unit: number, count: number): boolean {
  return limit.type === "TOKENS_LIMIT" && limit.unit === unit && limit.number === count;
}

function makeZaiWindow(
  limit: ZaiLimit | undefined,
  id: string,
  kind: "short" | "weekly",
  duration: number,
): UsageWindow | null {
  if (!limit) return null;
  const percentage = limit.percentage;
  if (
    typeof percentage !== "number" ||
    !Number.isFinite(percentage) ||
    percentage < 0 ||
    percentage > 100
  ) {
    throw ProviderClientError.unsupportedResponse();
  }
  let resetAt: Date | null = null;
  const nextResetTime = limit.nextResetTime;
  if (
    typeof nextResetTime === "number" &&
    Number.isFinite(nextResetTime) &&
    nextResetTime > 0
  ) {
    resetAt = new Date(nextResetTime);
  }
  const window = makeUsageWindow({
    id,
    kind,
    duration,
    resetAt,
    consumedFraction: percentage / 100,
  });
  if (!window) throw ProviderClientError.unsupportedResponse();
  return window;
}

export function decodeZaiUsage(
  data: Uint8Array,
  accountID: string,
  fetchedAt: Date,
): UsageSnapshot {
  let response: {
    code?: unknown;
    success?: unknown;
    data?: { limits?: ZaiLimit[] | null } | null;
  };
  try {
    response = JSON.parse(new TextDecoder().decode(data));
  } catch {
    throw ProviderClientError.unsupportedResponse();
  }

  if (response.code === 401 || response.code === 403) {
    throw ProviderClientError.reauthenticationRequired();
  }
  const success = response.success;
  if (success === false || !(success === true || response.code === 200)) {
    throw ProviderClientError.unsupportedResponse();
  }
  const limits = response.data?.limits;
  if (!Array.isArray(limits)) throw ProviderClientError.unsupportedResponse();

  const windows = [
    makeZaiWindow(
      limits.find((limit) => isTokenLimit(limit, 3, 5)),
      "zai-short",
      "short",
      18_000,
    ),
    makeZaiWindow(
      limits.find((limit) => isTokenLimit(limit, 6, 1)),
      "zai-weekly",
      "weekly",
      604_800,
    ),
  ].filter((window): window is UsageWindow => window !== null);
  if (windows.length === 0) throw ProviderClientError.unsupportedResponse();

  return {
    accountID,
    fetchedAt: fetchedAt.toISOString(),
    windows,
    balances: [],
  };
}

export class ZaiUsageClient {
  constructor(private readonly transport: HTTPTransport) {}

  async fetchUsage(
    accountID: string,
    apiKey: string,
    now: Date,
  ): Promise<UsageSnapshot> {
    if (!apiKey.trim()) throw ProviderClientError.reauthenticationRequired();
    const response = await this.transport.send({
      url: "https://api.z.ai/api/monitor/usage/quota/limit",
      method: "GET",
      // Z.ai's monitor API expects the raw Coding Plan key, no Bearer prefix.
      headers: { Authorization: apiKey },
    });
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return decodeZaiUsage(response.data, accountID, now);
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
