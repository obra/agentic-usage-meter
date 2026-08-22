// SuperGrok provider — port of SuperGrokCredential.swift,
// SuperGrokAuthDocumentDecoder.swift, SuperGrokOIDCRefreshClient.swift,
// SuperGrokUsageDecoder.swift, SuperGrokUsageAdapter.swift and
// SuperGrokDeviceAuthenticationFlow.swift.

import {
  makeUsageBalance,
  makeUsageWindow,
  type UsageBalance,
  type UsageSnapshot,
  type UsageWindow,
} from "../models.js";
import { ProviderClientError } from "../errors.js";
import { parseISO8601 } from "../dates.js";
import { formURLEncoded, type HTTPTransport } from "../http.js";

const SUPERGROK_CLIENT_VERSION = "0.2.118";

// ---------------------------------------------------------------------------
// Credential
// ---------------------------------------------------------------------------

export interface SuperGrokCredential {
  accessToken: string;
  email?: string;
  teamID?: string;
  userID?: string;
  authMode?: string;
  expiresAt?: string;
  refreshToken?: string;
  oidcIssuer?: string;
  oidcClientID?: string;
  createdAt?: string;
}

function normalized(value: string | undefined): string | undefined {
  const trimmed = value?.trim();
  return trimmed ? trimmed : undefined;
}

function normalizedLower(value: string | undefined): string | undefined {
  return normalized(value)?.toLowerCase();
}

export function superGrokIdentityKey(credential: SuperGrokCredential): string | undefined {
  const userID = normalizedLower(credential.userID);
  const teamID = normalizedLower(credential.teamID);
  if (userID && teamID) return `${userID}::${teamID}`;
  return userID ?? teamID ?? normalizedLower(credential.email);
}

export function superGrokNeedsRefresh(credential: SuperGrokCredential, at: Date): boolean {
  const refreshDeadline = at.getTime() + 5 * 60 * 1000;
  if (credential.expiresAt) {
    return new Date(credential.expiresAt).getTime() <= refreshDeadline;
  }
  if (credential.createdAt) {
    return (
      new Date(credential.createdAt).getTime() + 30 * 24 * 60 * 60 * 1000 <= refreshDeadline
    );
  }
  return false;
}

export function superGrokHasRefreshMaterial(credential: SuperGrokCredential): boolean {
  return (
    normalized(credential.authMode)?.toLowerCase() === "oidc" &&
    normalized(credential.refreshToken) !== undefined &&
    normalized(credential.oidcIssuer) !== undefined &&
    normalized(credential.oidcClientID) !== undefined
  );
}

// ---------------------------------------------------------------------------
// auth.json document decoder
// ---------------------------------------------------------------------------

export function decodeSuperGrokAuthDocument(data: Uint8Array): SuperGrokCredential {
  let root: unknown;
  try {
    root = JSON.parse(new TextDecoder().decode(data));
  } catch {
    throw ProviderClientError.unsupportedResponse();
  }
  if (typeof root !== "object" || root === null || Array.isArray(root)) {
    throw ProviderClientError.reauthenticationRequired();
  }
  const record = root as Record<string, unknown>;

  const str = (value: unknown): string | undefined =>
    typeof value === "string" && value.trim() !== "" ? value.trim() : undefined;

  let entry: Record<string, unknown> | undefined;
  if (str(record["key"])) {
    entry = record;
  } else {
    const candidates = Object.entries(record)
      .map(([scope, raw]) => ({ scope, entry: raw }))
      .filter(
        (candidate): candidate is { scope: string; entry: Record<string, unknown> } =>
          typeof candidate.entry === "object" &&
          candidate.entry !== null &&
          !Array.isArray(candidate.entry) &&
          str((candidate.entry as Record<string, unknown>)["key"]) !== undefined,
      );
    const priority = (scope: string): number => {
      if (scope.startsWith("https://auth.x.ai::")) return 0;
      if (scope === "https://accounts.x.ai/sign-in" || scope.includes("/sign-in")) return 1;
      return 2;
    };
    candidates.sort((lhs, rhs) => {
      const lhsPriority = priority(lhs.scope);
      const rhsPriority = priority(rhs.scope);
      if (lhsPriority !== rhsPriority) return lhsPriority - rhsPriority;
      return lhs.scope < rhs.scope ? -1 : lhs.scope > rhs.scope ? 1 : 0;
    });
    entry = candidates[0]?.entry;
  }

  if (!entry) throw ProviderClientError.reauthenticationRequired();
  const accessToken = str(entry["key"]);
  if (!accessToken) throw ProviderClientError.reauthenticationRequired();

  const credential: SuperGrokCredential = { accessToken };
  const assign = <K extends keyof SuperGrokCredential>(
    key: K,
    value: SuperGrokCredential[K] | undefined,
  ) => {
    if (value !== undefined) credential[key] = value;
  };
  assign("email", str(entry["email"]));
  assign("teamID", str(entry["team_id"]));
  assign("userID", str(entry["user_id"]));
  assign("authMode", str(entry["auth_mode"]));
  assign("expiresAt", parseISO8601(str(entry["expires_at"]) ?? "")?.toISOString());
  assign("refreshToken", str(entry["refresh_token"]));
  assign("oidcIssuer", str(entry["oidc_issuer"]));
  assign("oidcClientID", str(entry["oidc_client_id"]));
  assign("createdAt", parseISO8601(str(entry["create_time"]) ?? "")?.toISOString());
  if (!superGrokIdentityKey(credential) || !normalized(credential.userID)) {
    throw ProviderClientError.unsupportedResponse();
  }
  return credential;
}

// ---------------------------------------------------------------------------
// OIDC refresh (auth.x.ai)
// ---------------------------------------------------------------------------

const SUPERGROK_ISSUER_HOST = "auth.x.ai";
const SUPERGROK_DISCOVERY_URL = "https://auth.x.ai/.well-known/openid-configuration";

function validatedIssuer(value: string | undefined): string | undefined {
  const raw = normalized(value);
  if (!raw) return undefined;
  try {
    const url = new URL(raw);
    if (url.protocol !== "https:" || url.host !== SUPERGROK_ISSUER_HOST) return undefined;
    if (url.port || url.username || url.password || url.search || url.hash) return undefined;
    if (url.pathname !== "" && url.pathname !== "/") return undefined;
    return `https://${SUPERGROK_ISSUER_HOST}`;
  } catch {
    return undefined;
  }
}

function validatedTokenEndpoint(value: unknown): string | undefined {
  if (typeof value !== "string") return undefined;
  try {
    const url = new URL(value);
    if (url.protocol !== "https:" || url.host !== SUPERGROK_ISSUER_HOST) return undefined;
    if (url.port || url.username || url.password) return undefined;
    return value;
  } catch {
    return undefined;
  }
}

export class SuperGrokOIDCRefreshClient {
  constructor(private readonly transport: HTTPTransport) {}

  async refresh(credential: SuperGrokCredential, now: Date): Promise<SuperGrokCredential> {
    const refreshToken = normalized(credential.refreshToken);
    const clientID = normalized(credential.oidcClientID);
    const issuer = validatedIssuer(credential.oidcIssuer);
    if (
      normalized(credential.authMode)?.toLowerCase() !== "oidc" ||
      !refreshToken ||
      !clientID ||
      !issuer
    ) {
      throw ProviderClientError.reauthenticationRequired();
    }

    let discoveryResponse;
    try {
      discoveryResponse = await this.transport.send({
        url: SUPERGROK_DISCOVERY_URL,
        method: "GET",
        headers: {},
      });
    } catch {
      throw ProviderClientError.temporaryFailure();
    }
    if (discoveryResponse.statusCode === 429) {
      throw ProviderClientError.retryAfter(discoveryResponse.retryDate(now));
    }
    if (discoveryResponse.statusCode < 200 || discoveryResponse.statusCode >= 300) {
      throw ProviderClientError.temporaryFailure();
    }
    let tokenEndpoint: string | undefined;
    try {
      const discovery = JSON.parse(discoveryResponse.text()) as Record<string, unknown>;
      tokenEndpoint = validatedTokenEndpoint(discovery["token_endpoint"]);
    } catch {
      throw ProviderClientError.unsupportedResponse();
    }
    if (!tokenEndpoint) throw ProviderClientError.unsupportedResponse();

    let tokenResponse;
    try {
      tokenResponse = await this.transport.send({
        url: tokenEndpoint,
        method: "POST",
        headers: { "Content-Type": "application/x-www-form-urlencoded" },
        body: formURLEncoded([
          ["grant_type", "refresh_token"],
          ["refresh_token", refreshToken],
          ["client_id", clientID],
        ]),
      });
    } catch {
      throw ProviderClientError.temporaryFailure();
    }

    if (tokenResponse.statusCode >= 200 && tokenResponse.statusCode < 300) {
      let parsed: { access_token?: unknown; refresh_token?: unknown; expires_in?: unknown };
      try {
        parsed = JSON.parse(tokenResponse.text());
      } catch {
        throw ProviderClientError.unsupportedResponse();
      }
      const accessToken = normalized(
        typeof parsed.access_token === "string" ? parsed.access_token : undefined,
      );
      const expiresIn = parsed.expires_in;
      if (
        !accessToken ||
        (expiresIn !== undefined &&
          (typeof expiresIn !== "number" || !Number.isFinite(expiresIn) || expiresIn <= 0))
      ) {
        throw ProviderClientError.unsupportedResponse();
      }
      const newRefreshToken = normalized(
        typeof parsed.refresh_token === "string" ? parsed.refresh_token : undefined,
      );
      return {
        accessToken,
        ...(credential.email ? { email: credential.email } : {}),
        ...(credential.teamID ? { teamID: credential.teamID } : {}),
        ...(credential.userID ? { userID: credential.userID } : {}),
        ...(credential.authMode ? { authMode: credential.authMode } : {}),
        ...(typeof expiresIn === "number"
          ? { expiresAt: new Date(now.getTime() + expiresIn * 1000).toISOString() }
          : {}),
        refreshToken: newRefreshToken ?? refreshToken,
        oidcIssuer: issuer,
        oidcClientID: clientID,
        createdAt: now.toISOString(),
      };
    }
    if (tokenResponse.statusCode === 400) {
      let code: string | undefined;
      try {
        const parsed = JSON.parse(tokenResponse.text()) as { error?: unknown };
        code = typeof parsed.error === "string" ? parsed.error : undefined;
      } catch {
        code = undefined;
      }
      if (code === "invalid_grant" || code === "invalid_client") {
        throw ProviderClientError.reauthenticationRequired();
      }
      throw ProviderClientError.temporaryFailure();
    }
    if (tokenResponse.statusCode === 401 || tokenResponse.statusCode === 403) {
      throw ProviderClientError.reauthenticationRequired();
    }
    if (tokenResponse.statusCode === 429) {
      throw ProviderClientError.retryAfter(tokenResponse.retryDate(now));
    }
    throw ProviderClientError.temporaryFailure();
  }
}

// ---------------------------------------------------------------------------
// Usage decode
// ---------------------------------------------------------------------------

interface BillingCent {
  val?: unknown;
}

interface BillingConfig {
  creditUsagePercent?: unknown;
  currentPeriod?: { type?: unknown; start?: unknown; end?: unknown } | null;
  monthlyLimit?: BillingCent | null;
  used?: BillingCent | null;
  prepaidBalance?: BillingCent | null;
  billingPeriodStart?: unknown;
  billingPeriodEnd?: unknown;
}

function centVal(cent: BillingCent | null | undefined): number | undefined {
  const val = cent?.val;
  return typeof val === "number" && Number.isFinite(val) ? val : undefined;
}

function windowIdentityForPeriodType(
  type: unknown,
): { id: string; kind: "weekly" | "monthly" } | null {
  if (type === "USAGE_PERIOD_TYPE_WEEKLY") return { id: "supergrok-weekly", kind: "weekly" };
  if (type === "USAGE_PERIOD_TYPE_MONTHLY") return { id: "supergrok-monthly", kind: "monthly" };
  return null;
}

function currentWindow(config: BillingConfig): UsageWindow | null {
  const rawPercent = config.creditUsagePercent;
  const usedPercent = typeof rawPercent === "number" ? rawPercent : 0;
  if (!Number.isFinite(usedPercent) || usedPercent < 0 || usedPercent > 100) return null;
  const period = config.currentPeriod;
  if (!period) return null;
  const identity = windowIdentityForPeriodType(period.type);
  if (!identity) return null;
  const start =
    typeof period.start === "string" ? parseISO8601(period.start) : null;
  const end = typeof period.end === "string" ? parseISO8601(period.end) : null;
  if (!start || !end || end.getTime() <= start.getTime()) return null;
  return makeUsageWindow({
    id: identity.id,
    kind: identity.kind,
    duration: (end.getTime() - start.getTime()) / 1000,
    resetAt: end,
    consumedFraction: usedPercent / 100,
    reportedStartAt: start,
  });
}

function legacyWindow(config: BillingConfig): UsageWindow | null {
  const limit = centVal(config.monthlyLimit);
  const used = centVal(config.used);
  if (limit === undefined || used === undefined) return null;
  if (!(limit > 0) || used < 0 || used > limit) return null;
  const start =
    typeof config.billingPeriodStart === "string"
      ? parseISO8601(config.billingPeriodStart)
      : null;
  const end =
    typeof config.billingPeriodEnd === "string"
      ? parseISO8601(config.billingPeriodEnd)
      : null;
  if (!start || !end || end.getTime() <= start.getTime()) return null;
  return makeUsageWindow({
    id: "supergrok-monthly",
    kind: "monthly",
    duration: (end.getTime() - start.getTime()) / 1000,
    resetAt: end,
    consumedFraction: used / limit,
    reportedStartAt: start,
  });
}

function superGrokBalances(config: BillingConfig): UsageBalance[] {
  const prepaid = centVal(config.prepaidBalance);
  if (prepaid === undefined) return [];
  if (prepaid < 0) throw ProviderClientError.unsupportedResponse();
  const balance = makeUsageBalance({
    id: "supergrok-prepaid",
    label: "Extra usage",
    value: { state: "available", amount: prepaid / 100, unit: "USD" },
  });
  if (!balance) throw ProviderClientError.unsupportedResponse();
  return [balance];
}

export function decodeSuperGrokUsage(
  data: Uint8Array,
  accountID: string,
  fetchedAt: Date,
): UsageSnapshot {
  let response: { config?: BillingConfig | null };
  try {
    response = JSON.parse(new TextDecoder().decode(data));
  } catch {
    throw ProviderClientError.unsupportedResponse();
  }
  const config = response.config;
  if (!config) throw ProviderClientError.unsupportedResponse();
  const window = currentWindow(config) ?? legacyWindow(config);
  if (!window) throw ProviderClientError.unsupportedResponse();
  return {
    accountID,
    fetchedAt: fetchedAt.toISOString(),
    windows: [window],
    balances: superGrokBalances(config),
  };
}

// ---------------------------------------------------------------------------
// Usage client (billing request + OIDC retry)
// ---------------------------------------------------------------------------

function superGrokBillingRequest(credential: SuperGrokCredential) {
  return {
    url: "https://cli-chat-proxy.grok.com/v1/billing?format=credits",
    method: "GET",
    headers: {
      Authorization: `Bearer ${credential.accessToken}`,
      "X-XAI-Token-Auth": "xai-grok-cli",
      "x-userid": credential.userID ?? "",
      "x-grok-client-version": SUPERGROK_CLIENT_VERSION,
      "x-grok-client-mode": "headless",
    },
  };
}

export class SuperGrokUsageClient {
  private readonly refreshClient: SuperGrokOIDCRefreshClient;

  constructor(
    private readonly transport: HTTPTransport,
    refreshTransport?: HTTPTransport,
  ) {
    this.refreshClient = new SuperGrokOIDCRefreshClient(refreshTransport ?? transport);
  }

  // Returns the (possibly refreshed) snapshot plus the credential that
  // succeeded, so the caller can persist a refresh when one happened.
  async fetchUsage(
    accountID: string,
    stored: SuperGrokCredential,
    now: Date,
  ): Promise<{ snapshot: UsageSnapshot; credential: SuperGrokCredential }> {
    let credential = stored;
    if (!credential.accessToken || !normalized(credential.userID)) {
      throw ProviderClientError.reauthenticationRequired();
    }
    if (superGrokHasRefreshMaterial(credential) && superGrokNeedsRefresh(credential, now)) {
      credential = await this.refreshClient.refresh(credential, now);
    }

    let response = await this.transport.send(superGrokBillingRequest(credential));
    if (response.statusCode === 401 || response.statusCode === 403) {
      credential = await this.refreshClient.refresh(credential, now);
      response = await this.transport.send(superGrokBillingRequest(credential));
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return {
        snapshot: decodeSuperGrokUsage(response.data, accountID, now),
        credential,
      };
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
// Device authentication output parsing (the process runner lives in main)
// ---------------------------------------------------------------------------

export interface SuperGrokAuthorizationPrompt {
  verificationURL: string;
  userCode: string;
}

// Port of SuperGrokDeviceAuthOutputParser: feed it stdout chunks; it returns
// a prompt once both an https URL and an XXXX-XXXX code have appeared.
export class SuperGrokDeviceAuthOutputParser {
  private output = "";

  append(chunk: string): SuperGrokAuthorizationPrompt | null {
    this.output += chunk;
    if (this.output.length > 16_384) {
      this.output = this.output.slice(-16_384);
    }
    const urlMatch = /https:\/\/[^\s]+/.exec(this.output);
    const codeMatch = /[A-Z0-9]{4}-[A-Z0-9]{4}/.exec(this.output);
    if (!urlMatch || !codeMatch) return null;
    return { verificationURL: urlMatch[0], userCode: codeMatch[0] };
  }
}
