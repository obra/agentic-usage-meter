// MiMo provider — port of MiMoUsageAdapter.swift, MiMoUsageDecoder.swift and
// the cookie canonicalization from MiMoLoginSession.swift.

import {
  makeAvailableBalance,
  type UsageSnapshot,
} from "../models.js";
import { ProviderClientError } from "../errors.js";
import { flexibleNumber } from "../dates.js";
import type { HTTPTransport } from "../http.js";
import type { SessionCookie } from "./claude.js";

export function isMiMoDomain(domain: string): boolean {
  const cleaned = domain.toLowerCase().replace(/^\.+|\.+$/g, "");
  return cleaned === "xiaomimimo.com" || cleaned.endsWith(".xiaomimimo.com");
}

// Canonical cookie header: unexpired cookies sorted by name so an unchanged
// session produces a byte-identical header (port of MiMoLoginDetector).
export function mimoCookieHeader(cookies: SessionCookie[], now = new Date()): string | null {
  const selected = cookies.filter(
    (cookie) =>
      cookie.value !== "" &&
      isMiMoDomain(cookie.domain) &&
      (cookie.expirationDate === undefined || cookie.expirationDate * 1000 > now.getTime()),
  );
  if (selected.length === 0) return null;
  return selected
    .slice()
    .sort((lhs, rhs) =>
      lhs.name === rhs.name
        ? lhs.value < rhs.value
          ? -1
          : lhs.value > rhs.value
            ? 1
            : 0
        : lhs.name < rhs.name
          ? -1
          : 1,
    )
    .map((cookie) => `${cookie.name}=${cookie.value}`)
    .join("; ");
}

export function decodeMiMoUsage(
  data: Uint8Array,
  accountID: string,
  fetchedAt: Date,
): UsageSnapshot {
  let response: {
    code?: unknown;
    data?: {
      monthUsage?: { items?: { name?: unknown; used?: unknown; limit?: unknown }[] | null } | null;
    } | null;
  };
  try {
    response = JSON.parse(new TextDecoder().decode(data));
  } catch {
    throw ProviderClientError.unsupportedResponse();
  }

  if (response.code === 401 || response.code === 403) {
    throw ProviderClientError.reauthenticationRequired();
  }
  if (response.code !== 0) throw ProviderClientError.unsupportedResponse();

  const items = response.data?.monthUsage?.items;
  const bundle = Array.isArray(items)
    ? items.find((item) => item.name === "month_total_token")
    : undefined;
  const limit = bundle ? flexibleNumber(bundle.limit) : undefined;
  const used = bundle ? flexibleNumber(bundle.used) : undefined;
  if (
    limit === undefined ||
    !Number.isFinite(limit) ||
    limit <= 0 ||
    used === undefined ||
    !Number.isFinite(used) ||
    used < 0
  ) {
    throw ProviderClientError.unsupportedResponse();
  }

  // The plan renews monthly but the response carries no reset timestamp, so
  // the bundle is presented as a remaining balance (no invented reset).
  const remaining = Math.max(limit - used, 0);
  const balance = makeAvailableBalance({
    id: "mimo-monthly-tokens",
    label: "Monthly tokens",
    remainingAmount: remaining,
    unit: "tokens",
  });
  if (!balance) throw ProviderClientError.unsupportedResponse();
  return {
    accountID,
    fetchedAt: fetchedAt.toISOString(),
    windows: [],
    balances: [balance],
  };
}

export class MiMoUsageClient {
  constructor(private readonly transport: HTTPTransport) {}

  async fetchUsage(
    accountID: string,
    cookieHeaderValue: string,
    now: Date,
  ): Promise<UsageSnapshot> {
    if (!cookieHeaderValue.trim()) throw ProviderClientError.reauthenticationRequired();
    const response = await this.transport.send({
      url: "https://platform.xiaomimimo.com/api/v1/tokenPlan/usage",
      method: "GET",
      headers: {
        Cookie: cookieHeaderValue,
        Accept: "application/json",
      },
    });
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return decodeMiMoUsage(response.data, accountID, now);
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
