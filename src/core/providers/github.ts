// GitHub Copilot provider — port of GitHubCopilotUsageAdapter.swift,
// GitHubCopilotUsageDecoder.swift, GitHubCopilotOAuthRequests.swift and
// GitHubCopilotOAuthFlow.swift.

import {
  makeUsageWindow,
  type UsageSnapshot,
  type UsageWindow,
} from "../models.js";
import { ProviderClientError } from "../errors.js";
import {
  flexibleNumber,
  flexibleString,
  oneMonthBeforeUTC,
  parseISO8601,
  parseUTCDateOnly,
} from "../dates.js";
import { formURLEncoded, type HTTPTransport } from "../http.js";

// ---------------------------------------------------------------------------
// Usage decode
// ---------------------------------------------------------------------------

interface GitHubCopilotUsageResult {
  snapshot: UsageSnapshot;
  plan?: string;
  userID?: string;
}

function quotaLabel(key: string): string {
  const words = key.replace(/_/g, " ");
  return words.slice(0, 1).toUpperCase() + words.slice(1);
}

function parseResetDate(value: unknown): Date | null {
  if (typeof value !== "string") return null;
  return parseISO8601(value) ?? parseUTCDateOnly(value);
}

export function decodeGitHubCopilotUsage(
  data: Uint8Array,
  accountID: string,
  fetchedAt: Date,
): GitHubCopilotUsageResult {
  let response: Record<string, unknown>;
  try {
    response = JSON.parse(new TextDecoder().decode(data));
  } catch {
    throw ProviderClientError.unsupportedResponse();
  }

  const plan = flexibleString(response["copilot_plan"]) ?? flexibleString(response["plan"]);
  const userID = flexibleString(response["user_id"]) ?? flexibleString(response["id"]);
  const resetAt =
    parseResetDate(response["quota_reset_date_utc"]) ??
    parseResetDate(response["quota_reset_date"]) ??
    parseResetDate(response["limited_user_reset_date"]);

  const quotaSnapshots = (response["quota_snapshots"] ?? {}) as Record<string, unknown>;
  const limitedEntries = Object.entries(quotaSnapshots)
    .map(([key, raw]) => {
      const quota = (raw ?? {}) as Record<string, unknown>;
      return {
        key,
        unlimited: quota["unlimited"] === true,
        entitlement: flexibleNumber(quota["entitlement"]),
        remaining: flexibleNumber(quota["remaining"]),
      };
    })
    .filter(
      (quota) =>
        !quota.unlimited && quota.entitlement !== undefined && quota.entitlement > 0,
    )
    .sort((lhs, rhs) => (lhs.key < rhs.key ? -1 : lhs.key > rhs.key ? 1 : 0));

  const windows: UsageWindow[] = [];
  if (limitedEntries.length > 0) {
    if (!resetAt) throw ProviderClientError.unsupportedResponse();
    const startAt = oneMonthBeforeUTC(resetAt);
    const duration = (resetAt.getTime() - startAt.getTime()) / 1000;
    if (!(duration > 0)) throw ProviderClientError.unsupportedResponse();
    for (const quota of limitedEntries) {
      const entitlement = quota.entitlement!;
      const remaining = quota.remaining;
      if (remaining === undefined || !Number.isFinite(remaining)) {
        throw ProviderClientError.unsupportedResponse();
      }
      const clampedRemaining = Math.min(Math.max(remaining, 0), entitlement);
      const window = makeUsageWindow({
        id: `github-copilot-${quota.key.replace(/_/g, "-")}`,
        kind: "monthly",
        duration,
        resetAt,
        consumedFraction: (entitlement - clampedRemaining) / entitlement,
        label: quotaLabel(quota.key),
      });
      if (!window) throw ProviderClientError.unsupportedResponse();
      windows.push(window);
    }
  }

  return {
    snapshot: {
      accountID,
      fetchedAt: fetchedAt.toISOString(),
      windows,
      balances: [],
    },
    ...(plan !== undefined ? { plan } : {}),
    ...(userID !== undefined ? { userID } : {}),
  };
}

// ---------------------------------------------------------------------------
// Usage client
// ---------------------------------------------------------------------------

export interface GitHubCopilotCredential {
  accessToken: string;
  userID: string;
  login: string;
}

export class GitHubCopilotUsageClient {
  constructor(private readonly transport: HTTPTransport) {}

  async fetchUsage(
    accountID: string,
    credential: GitHubCopilotCredential,
    now: Date,
  ): Promise<UsageSnapshot> {
    if (!credential.accessToken || !credential.userID || !credential.login) {
      throw ProviderClientError.reauthenticationRequired();
    }
    const response = await this.transport.send({
      url: "https://api.github.com/copilot_internal/user",
      method: "GET",
      headers: {
        Authorization: `token ${credential.accessToken}`,
        Accept: "application/json",
        "Editor-Version": "vscode/1.96.2",
        "X-GitHub-Api-Version": "2025-04-01",
      },
    });
    if (response.statusCode >= 200 && response.statusCode < 300) {
      const result = decodeGitHubCopilotUsage(response.data, accountID, now);
      if (result.userID && result.userID !== credential.userID) {
        throw ProviderClientError.credentialMismatch();
      }
      return result.snapshot;
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
// Device OAuth flow
// ---------------------------------------------------------------------------

export const GITHUB_COPILOT_CLIENT_ID = "Ov23ctDVkRmgkPke0Mmm";
const GITHUB_DEVICE_CODE_ENDPOINT = "https://github.com/login/device/code";
const GITHUB_ACCESS_TOKEN_ENDPOINT = "https://github.com/login/oauth/access_token";

function githubRequest(url: string, form: [string, string][]) {
  return {
    url,
    method: "POST",
    headers: {
      "Content-Type": "application/x-www-form-urlencoded",
      Accept: "application/json",
    },
    body: formURLEncoded(form),
  };
}

export const githubDeviceAuthorizationRequest = () =>
  githubRequest(GITHUB_DEVICE_CODE_ENDPOINT, [["client_id", GITHUB_COPILOT_CLIENT_ID]]);

export const githubAccessTokenRequest = (deviceCode: string) =>
  githubRequest(GITHUB_ACCESS_TOKEN_ENDPOINT, [
    ["client_id", GITHUB_COPILOT_CLIENT_ID],
    ["device_code", deviceCode],
    ["grant_type", "urn:ietf:params:oauth:grant-type:device_code"],
  ]);

export interface GitHubAuthorizationPrompt {
  verificationURL: string;
  userCode: string;
  expiresAt: Date;
}

export class GitHubCopilotOAuthFlow {
  constructor(
    private readonly transport: HTTPTransport,
    private readonly openBrowser: (url: string) => Promise<boolean>,
    private readonly now: () => Date = () => new Date(),
    private readonly sleep: (seconds: number) => Promise<void> = (seconds) =>
      new Promise((resolve) => setTimeout(resolve, seconds * 1000)),
  ) {}

  async authenticate(
    onPrompt: (prompt: GitHubAuthorizationPrompt) => void = () => {},
  ): Promise<GitHubCopilotCredential> {
    const authorizationResponse = await this.transport.send(githubDeviceAuthorizationRequest());
    if (authorizationResponse.statusCode !== 200) {
      throw ProviderClientError.temporaryFailure();
    }
    let authorization: {
      device_code?: unknown;
      user_code?: unknown;
      verification_uri?: unknown;
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
    const verificationURI = authorization.verification_uri;
    const expiresIn = authorization.expires_in;
    const intervalSeconds = authorization.interval;
    if (
      typeof deviceCode !== "string" ||
      deviceCode === "" ||
      typeof userCode !== "string" ||
      userCode === "" ||
      typeof verificationURI !== "string" ||
      typeof expiresIn !== "number" ||
      expiresIn <= 0 ||
      typeof intervalSeconds !== "number" ||
      intervalSeconds <= 0
    ) {
      throw ProviderClientError.unsupportedResponse();
    }
    try {
      const url = new URL(verificationURI);
      if (url.protocol !== "https:" || url.host !== "github.com") throw new Error("bad");
    } catch {
      throw ProviderClientError.unsupportedResponse();
    }

    onPrompt({
      verificationURL: verificationURI,
      userCode,
      expiresAt: new Date(this.now().getTime() + expiresIn * 1000),
    });
    if (!(await this.openBrowser(verificationURI))) {
      throw new Error("browser-open-failed");
    }

    let interval = intervalSeconds;
    let remaining = expiresIn;
    while (remaining > 0) {
      const response = await this.transport.send(githubAccessTokenRequest(deviceCode));
      let token: { access_token?: unknown; error?: unknown };
      try {
        token = JSON.parse(response.text());
      } catch {
        throw ProviderClientError.unsupportedResponse();
      }
      if (typeof token.access_token === "string" && token.access_token !== "") {
        return await this.identity(token.access_token);
      }
      const error = typeof token.error === "string" ? token.error : undefined;
      if (error === "authorization_pending") {
        // keep polling
      } else if (error === "slow_down") {
        interval += 5;
      } else {
        throw ProviderClientError.reauthenticationRequired();
      }
      await this.sleep(interval);
      remaining -= interval;
    }
    throw ProviderClientError.reauthenticationRequired();
  }

  private async identity(accessToken: string): Promise<GitHubCopilotCredential> {
    const response = await this.transport.send({
      url: "https://api.github.com/user",
      method: "GET",
      headers: {
        Authorization: `Bearer ${accessToken}`,
        Accept: "application/vnd.github+json",
      },
    });
    if (response.statusCode !== 200) {
      throw ProviderClientError.reauthenticationRequired();
    }
    let identity: { login?: unknown; id?: unknown };
    try {
      identity = JSON.parse(response.text());
    } catch {
      throw ProviderClientError.unsupportedResponse();
    }
    if (
      typeof identity.login !== "string" ||
      identity.login === "" ||
      typeof identity.id !== "number" ||
      !(identity.id > 0)
    ) {
      throw ProviderClientError.unsupportedResponse();
    }
    return {
      accessToken,
      userID: String(identity.id),
      login: identity.login,
    };
  }
}
