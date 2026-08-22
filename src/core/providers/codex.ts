// Codex provider — port of CodexUsageClient.swift, CodexOAuthRequests.swift,
// CodexOAuthToken.swift and CodexOAuthFlow.swift.

import { makeUsageBalance, makeUsageWindow, type OAuthCredential, type UsageBalance, type UsageSnapshot, type UsageWindow, type UsageWindowKind } from "../models.js";
import { ProviderClientError } from "../errors.js";
import { decodeJWTPayload } from "../dates.js";
import { formURLEncoded, type HTTPTransport } from "../http.js";

// ---------------------------------------------------------------------------
// Usage decode
// ---------------------------------------------------------------------------

interface CodexWindow {
  used_percent?: unknown;
  limit_window_seconds?: unknown;
  reset_at?: unknown;
}

interface CodexUsageResponse {
  rate_limit?: {
    primary_window?: CodexWindow | null;
    secondary_window?: CodexWindow | null;
  } | null;
  credits?: {
    has_credits?: unknown;
    unlimited?: unknown;
    balance?: unknown;
  } | null;
}

function windowKindForDuration(duration: number): UsageWindowKind | null {
  if (duration === 18_000) return "short";
  if (duration === 604_800) return "weekly";
  return null;
}

function normalizedBalances(credits: CodexUsageResponse["credits"]): UsageBalance[] {
  if (!credits) return [];
  let value: UsageBalance["value"];
  if (credits.unlimited === true) {
    value = { state: "unlimited" };
  } else if (credits.has_credits !== true) {
    value = { state: "disabled" };
  } else {
    if (typeof credits.balance !== "string") {
      throw ProviderClientError.unsupportedResponse();
    }
    const amount = Number(credits.balance);
    if (!Number.isFinite(amount) || amount < 0) {
      throw ProviderClientError.unsupportedResponse();
    }
    value = { state: "available", amount, unit: "credits" };
  }
  const balance = makeUsageBalance({
    id: "codex-chatgpt-credits",
    label: "ChatGPT credits",
    value,
  });
  if (!balance) throw ProviderClientError.unsupportedResponse();
  return [balance];
}

export function decodeCodexUsage(
  data: Uint8Array,
  accountID: string,
  fetchedAt: Date,
): UsageSnapshot {
  let response: CodexUsageResponse;
  try {
    response = JSON.parse(new TextDecoder().decode(data)) as CodexUsageResponse;
  } catch {
    throw ProviderClientError.unsupportedResponse();
  }

  const candidates = [
    response.rate_limit?.primary_window,
    response.rate_limit?.secondary_window,
  ].filter((candidate): candidate is CodexWindow => candidate != null);

  const windowsByKind = new Map<UsageWindowKind, UsageWindow>();
  for (const candidate of candidates) {
    const duration = candidate.limit_window_seconds;
    const usedPercent = candidate.used_percent;
    const resetAt = candidate.reset_at;
    if (
      typeof duration !== "number" ||
      typeof usedPercent !== "number" ||
      typeof resetAt !== "number"
    ) {
      throw ProviderClientError.unsupportedResponse();
    }
    const kind = windowKindForDuration(duration);
    if (!kind) continue;
    if (
      windowsByKind.has(kind) ||
      !Number.isFinite(usedPercent) ||
      usedPercent < 0 ||
      usedPercent > 100 ||
      !Number.isFinite(resetAt) ||
      resetAt <= 0
    ) {
      throw ProviderClientError.unsupportedResponse();
    }
    const window = makeUsageWindow({
      id: `codex-${kind}`,
      kind,
      duration,
      resetAt: new Date(resetAt * 1000),
      consumedFraction: usedPercent / 100,
    });
    if (!window) throw ProviderClientError.unsupportedResponse();
    windowsByKind.set(kind, window);
  }

  const windows = [windowsByKind.get("short"), windowsByKind.get("weekly")].filter(
    (window): window is UsageWindow => window != null,
  );
  if (windows.length === 0) throw ProviderClientError.unsupportedResponse();

  return {
    accountID,
    fetchedAt: fetchedAt.toISOString(),
    windows,
    balances: normalizedBalances(response.credits),
  };
}

// ---------------------------------------------------------------------------
// Usage client
// ---------------------------------------------------------------------------

export class CodexUsageClient {
  constructor(private readonly transport: HTTPTransport) {}

  async fetchUsage(
    accountID: string,
    oauth: OAuthCredential,
    now: Date,
  ): Promise<UsageSnapshot> {
    if (!oauth.accessToken || !oauth.accountID) {
      throw ProviderClientError.credentialMismatch();
    }
    const response = await this.transport.send({
      url: "https://chatgpt.com/backend-api/wham/usage",
      method: "GET",
      headers: {
        Authorization: `Bearer ${oauth.accessToken}`,
        "ChatGPT-Account-Id": oauth.accountID,
        "User-Agent": "codex-cli",
      },
    });
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return decodeCodexUsage(response.data, accountID, now);
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
// OAuth requests / tokens
// ---------------------------------------------------------------------------

export const CODEX_CLIENT_ID = "app_EMoamEEZ73f0CkXaXp7hrann";
const CODEX_AUTHORIZATION_ENDPOINT = "https://auth.openai.com/oauth/authorize";
const CODEX_TOKEN_ENDPOINT = "https://auth.openai.com/oauth/token";

export function codexAuthorizationURL(input: {
  redirectURL: string;
  codeChallenge: string;
  state: string;
}): string {
  const url = new URL(CODEX_AUTHORIZATION_ENDPOINT);
  url.searchParams.set("response_type", "code");
  url.searchParams.set("client_id", CODEX_CLIENT_ID);
  url.searchParams.set("redirect_uri", input.redirectURL);
  url.searchParams.set(
    "scope",
    "openid profile email offline_access api.connectors.read api.connectors.invoke",
  );
  url.searchParams.set("code_challenge", input.codeChallenge);
  url.searchParams.set("code_challenge_method", "S256");
  url.searchParams.set("id_token_add_organizations", "true");
  url.searchParams.set("codex_cli_simplified_flow", "true");
  url.searchParams.set("state", input.state);
  url.searchParams.set("originator", "codex_cli_rs");
  url.searchParams.set("prompt", "select_account");
  return url.toString();
}

export function codexTokenExchangeRequest(input: {
  code: string;
  redirectURL: string;
  verifier: string;
}) {
  return {
    url: CODEX_TOKEN_ENDPOINT,
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: formURLEncoded([
      ["grant_type", "authorization_code"],
      ["code", input.code],
      ["redirect_uri", input.redirectURL],
      ["client_id", CODEX_CLIENT_ID],
      ["code_verifier", input.verifier],
    ]),
  };
}

export function codexRefreshRequest(refreshToken: string) {
  return {
    url: CODEX_TOKEN_ENDPOINT,
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      client_id: CODEX_CLIENT_ID,
      grant_type: "refresh_token",
      refresh_token: refreshToken,
    }),
  };
}

export interface CodexOAuthIdentity {
  email?: string;
  plan?: string;
  userID?: string;
  accountID?: string;
}

export interface CodexOAuthResult {
  credential: OAuthCredential;
  identity: CodexOAuthIdentity;
}

function identityFromIDToken(idToken: string): CodexOAuthIdentity {
  const claims = decodeJWTPayload(idToken);
  if (!claims) throw ProviderClientError.unsupportedResponse();
  const auth = claims["https://api.openai.com/auth"] as
    | Record<string, unknown>
    | undefined;
  const profile = claims["https://api.openai.com/profile"] as
    | Record<string, unknown>
    | undefined;
  const stringClaim = (value: unknown): string | undefined =>
    typeof value === "string" && value.length > 0 ? value : undefined;
  const identity: CodexOAuthIdentity = {};
  const email = stringClaim(claims["email"]) ?? stringClaim(profile?.["email"]);
  const plan = stringClaim(auth?.["chatgpt_plan_type"]);
  const userID = stringClaim(auth?.["chatgpt_user_id"]) ?? stringClaim(auth?.["user_id"]);
  const accountID = stringClaim(auth?.["chatgpt_account_id"]);
  if (email) identity.email = email;
  if (plan) identity.plan = plan;
  if (userID) identity.userID = userID;
  if (accountID) identity.accountID = accountID;
  return identity;
}

function accessTokenExpiration(token: string): Date | undefined {
  const claims = decodeJWTPayload(token);
  const exp = claims?.["exp"];
  return typeof exp === "number" && Number.isFinite(exp)
    ? new Date(exp * 1000)
    : undefined;
}

export function decodeCodexInitialToken(data: Uint8Array): CodexOAuthResult {
  let response: { access_token?: unknown; refresh_token?: unknown; id_token?: unknown };
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
    typeof response.id_token !== "string" ||
    response.id_token === ""
  ) {
    throw ProviderClientError.unsupportedResponse();
  }
  const identity = identityFromIDToken(response.id_token);
  const expiresAt = accessTokenExpiration(response.access_token);
  const credential: OAuthCredential = {
    accessToken: response.access_token,
    refreshToken: response.refresh_token,
    idToken: response.id_token,
  };
  if (identity.accountID) credential.accountID = identity.accountID;
  if (expiresAt) credential.expiresAt = expiresAt.toISOString();
  return { credential, identity };
}

export function applyCodexRefresh(data: Uint8Array, original: CodexOAuthResult): CodexOAuthResult {
  let response: { access_token?: unknown; refresh_token?: unknown; id_token?: unknown };
  try {
    response = JSON.parse(new TextDecoder().decode(data));
  } catch {
    throw ProviderClientError.unsupportedResponse();
  }
  const nonempty = (value: unknown): string | undefined =>
    typeof value === "string" && value.length > 0 ? value : undefined;

  const accessToken = nonempty(response.access_token) ?? original.credential.accessToken;
  const refreshToken = nonempty(response.refresh_token) ?? original.credential.refreshToken;
  const idToken = nonempty(response.id_token) ?? original.credential.idToken;
  if (!accessToken) throw ProviderClientError.unsupportedResponse();

  const refreshedIDToken = nonempty(response.id_token);
  const identity = refreshedIDToken ? identityFromIDToken(refreshedIDToken) : original.identity;
  const expiresAt =
    accessTokenExpiration(accessToken) ??
    (original.credential.expiresAt ? new Date(original.credential.expiresAt) : undefined);
  const accountID = identity.accountID ?? original.credential.accountID;
  const credential: OAuthCredential = { accessToken };
  if (refreshToken) credential.refreshToken = refreshToken;
  if (idToken) credential.idToken = idToken;
  if (accountID) credential.accountID = accountID;
  if (expiresAt) credential.expiresAt = expiresAt.toISOString();
  return { credential, identity };
}

// ---------------------------------------------------------------------------
// OAuth flow (loopback redirect). The loopback server and browser opening are
// injected so this stays platform-neutral and testable.
// ---------------------------------------------------------------------------

export interface LoopbackServerHandle {
  callbackURL: string;
  waitForCode(): Promise<string>;
  cancel(): void;
}

export type BrowserOpener = (url: string) => Promise<boolean>;
export type LoopbackStarter = (expectedState: string) => Promise<LoopbackServerHandle>;

export class CodexOAuthFlow {
  constructor(
    private readonly transport: HTTPTransport,
    private readonly openBrowser: BrowserOpener,
    private readonly startLoopback: LoopbackStarter,
  ) {}

  async authenticate(generate: {
    pkce(): { verifier: string; challenge: string };
    state(): string;
  }): Promise<CodexOAuthResult> {
    const pkce = generate.pkce();
    const state = generate.state();
    const server = await this.startLoopback(state);
    try {
      const authorizationURL = codexAuthorizationURL({
        redirectURL: server.callbackURL,
        codeChallenge: pkce.challenge,
        state,
      });
      if (!(await this.openBrowser(authorizationURL))) {
        throw new Error("browser-open-failed");
      }
      const code = await server.waitForCode();
      const response = await this.transport.send(
        codexTokenExchangeRequest({
          code,
          redirectURL: server.callbackURL,
          verifier: pkce.verifier,
        }),
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw ProviderClientError.reauthenticationRequired();
      }
      return decodeCodexInitialToken(response.data);
    } finally {
      server.cancel();
    }
  }

  async refresh(current: CodexOAuthResult): Promise<CodexOAuthResult> {
    const refreshToken = current.credential.refreshToken;
    if (!refreshToken) throw ProviderClientError.reauthenticationRequired();
    let response;
    try {
      response = await this.transport.send(codexRefreshRequest(refreshToken));
    } catch {
      throw ProviderClientError.temporaryFailure();
    }
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return applyCodexRefresh(response.data, current);
    }
    if ([400, 401, 403].includes(response.statusCode)) {
      throw ProviderClientError.reauthenticationRequired();
    }
    throw ProviderClientError.temporaryFailure();
  }
}
