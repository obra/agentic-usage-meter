// Factory provider — port of FactoryUsageAdapter.swift and
// FactoryUsageDecoder.swift.

import {
  makeUsageBalance,
  makeUsageWindow,
  type UsageBalance,
  type UsageSnapshot,
  type UsageWindow,
  type UsageWindowKind,
} from "../models.js";
import { ProviderClientError } from "../errors.js";
import { parseISO8601 } from "../dates.js";
import type { HTTPTransport } from "../http.js";

interface FactoryWindowPayload {
  usedPercent?: unknown;
  windowEnd?: unknown;
}

interface FactoryPool {
  fiveHour?: FactoryWindowPayload | null;
  weekly?: FactoryWindowPayload | null;
  monthly?: FactoryWindowPayload | null;
}

function appendPoolWindows(
  pool: FactoryPool,
  poolID: string,
  poolLabel: string,
  windows: UsageWindow[],
): void {
  const candidates: [string, UsageWindowKind, number, FactoryWindowPayload | null | undefined][] = [
    ["five-hour", "short", 18_000, pool.fiveHour],
    ["weekly", "weekly", 604_800, pool.weekly],
    ["monthly", "monthly", 2_592_000, pool.monthly],
  ];
  for (const [name, kind, duration, value] of candidates) {
    if (!value) continue;
    const usedPercent = value.usedPercent;
    if (
      typeof usedPercent !== "number" ||
      !Number.isFinite(usedPercent) ||
      usedPercent < 0 ||
      usedPercent > 100
    ) {
      throw ProviderClientError.unsupportedResponse();
    }
    let resetAt: Date | null;
    if (typeof value.windowEnd === "string" && value.windowEnd !== "") {
      resetAt = parseISO8601(value.windowEnd);
      if (!resetAt) throw ProviderClientError.unsupportedResponse();
    } else {
      if (usedPercent !== 0) throw ProviderClientError.unsupportedResponse();
      resetAt = null;
    }
    const window = makeUsageWindow({
      id: `factory-${poolID}-${name}`,
      kind,
      duration,
      resetAt,
      consumedFraction: usedPercent / 100,
      label: poolLabel,
    });
    if (!window) throw ProviderClientError.unsupportedResponse();
    windows.push(window);
  }
}

export function decodeFactoryUsage(
  data: Uint8Array,
  accountID: string,
  fetchedAt: Date,
): UsageSnapshot {
  let response: {
    usesTokenRateLimitsBilling?: unknown;
    limits?: { standard?: FactoryPool | null; core?: FactoryPool | null } | null;
    extraUsageBalanceCents?: unknown;
    extraUsageAllowed?: unknown;
  };
  try {
    response = JSON.parse(new TextDecoder().decode(data));
  } catch {
    throw ProviderClientError.unsupportedResponse();
  }

  if (response.usesTokenRateLimitsBilling !== true) {
    throw ProviderClientError.unsupportedResponse();
  }

  const windows: UsageWindow[] = [];
  if (response.limits?.standard) {
    appendPoolWindows(response.limits.standard, "standard", "Standard", windows);
  }
  if (response.limits?.core) {
    appendPoolWindows(response.limits.core, "core", "Droid Core", windows);
  }

  let balances: UsageBalance[];
  if (response.extraUsageAllowed === false) {
    const disabled = makeUsageBalance({
      id: "factory-extra-usage",
      label: "Extra usage",
      value: { state: "disabled" },
    });
    if (!disabled) throw ProviderClientError.unsupportedResponse();
    balances = [disabled];
  } else if (typeof response.extraUsageBalanceCents === "number") {
    const cents = response.extraUsageBalanceCents;
    if (!Number.isFinite(cents) || cents < 0) {
      throw ProviderClientError.unsupportedResponse();
    }
    const balance = makeUsageBalance({
      id: "factory-extra-usage",
      label: "Extra usage",
      value: { state: "available", amount: cents / 100, unit: "USD" },
    });
    if (!balance) throw ProviderClientError.unsupportedResponse();
    balances = [balance];
  } else {
    balances = [];
  }

  if (windows.length === 0 && balances.length === 0) {
    throw ProviderClientError.unsupportedResponse();
  }
  return {
    accountID,
    fetchedAt: fetchedAt.toISOString(),
    windows,
    balances,
  };
}

export class FactoryUsageClient {
  constructor(private readonly transport: HTTPTransport) {}

  async fetchUsage(
    accountID: string,
    apiKey: string,
    now: Date,
  ): Promise<UsageSnapshot> {
    if (!apiKey.trim()) throw ProviderClientError.reauthenticationRequired();
    const response = await this.transport.send({
      url: "https://api.factory.ai/api/billing/limits",
      method: "GET",
      headers: { Authorization: `Bearer ${apiKey}` },
    });
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return decodeFactoryUsage(response.data, accountID, now);
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
