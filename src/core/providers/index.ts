// Unified provider dispatch — the port of the adapter layer wired in
// AgenticUsageMeterApp.swift (CredentialUsageAdapter for codex/kimi, the
// per-provider adapters for the rest, and the web-profile-backed clients for
// claude/opencode/mimo).

import type { AccountCredential, OAuthCredential, SubscriptionAccount, UsageSnapshot } from "../models.js";
import { oauthCredentialIsExpired } from "../models.js";
import { ProviderClientError, isProviderClientError } from "../errors.js";
import type { HTTPTransport } from "../http.js";
import {
  loadCredential,
  saveCredential,
  type CredentialStore,
} from "../credentials.js";
import { ClaudeUsageClient, ClaudeWebUsageClient, claudeAPICookies, type SessionCookie } from "./claude.js";
import { CodexUsageClient } from "./codex.js";
import { KimiOAuthFlow, KimiUsageClient, type KimiDeviceInfo } from "./kimi.js";
import { GitHubCopilotUsageClient } from "./github.js";
import { MiniMaxUsageClient } from "./minimax.js";
import { FactoryUsageClient } from "./factory.js";
import { ZaiUsageClient } from "./zai.js";
import { MiMoUsageClient, mimoCookieHeader } from "./mimo.js";
import {
  OpenCodeDashboardUsageClient,
  decodeOpenCodeGoUsage,
  decodeOpenCodeZenUsage,
  openCodeAuthCookie,
} from "./opencode.js";
import { SuperGrokUsageClient, type SuperGrokCredential } from "./supergrok.js";

// Reads the current cookies of an account's isolated session partition;
// returns null when the account has no live session (e.g. in tests).
export type CookieSource = (partition: string) => Promise<SessionCookie[] | null>;

export interface AdapterEnvironment {
  transport: HTTPTransport;
  noRedirectTransport: HTTPTransport;
  credentialStore: CredentialStore;
  cookieSource: CookieSource;
  kimiDevice: (accountID: string) => KimiDeviceInfo;
  now: () => Date;
}

export interface FetchResult {
  snapshot: UsageSnapshot;
  // Set when a credential refresh happened while fetching; the caller must
  // persist it.
  updatedCredential?: AccountCredential;
}

async function loadTypedCredential<T extends AccountCredential>(
  env: AdapterEnvironment,
  accountID: string,
  kind: T["kind"],
): Promise<T> {
  let credential: AccountCredential | null;
  try {
    credential = await loadCredential<AccountCredential>(env.credentialStore, accountID);
  } catch {
    throw ProviderClientError.credentialMismatch();
  }
  if (!credential || credential.kind !== kind) {
    throw ProviderClientError.reauthenticationRequired();
  }
  return credential as T;
}

export class ProviderAdapters {
  constructor(private readonly env: AdapterEnvironment) {}

  // Mirrors ProviderAccountAdapter.canRecoverAuthenticationWithoutReconnect:
  // adapters with refresh material may retry even after a reauthentication
  // failure was recorded.
  canRecoverAuthenticationWithoutReconnect(provider: SubscriptionAccount["provider"]): boolean {
    return provider === "kimi" || provider === "supergrok";
  }

  async removeAuthentication(account: SubscriptionAccount): Promise<void> {
    await this.env.credentialStore.delete(account.id);
  }

  async fetchUsage(account: SubscriptionAccount): Promise<FetchResult> {
    const now = this.env.now();
    switch (account.provider) {
      case "claude":
        return this.fetchClaude(account, now);
      case "codex":
        return this.fetchCodex(account, now);
      case "kimi":
        return this.fetchKimi(account, now);
      case "github-copilot": {
        const credential = await loadTypedCredential<{ kind: "github-copilot"; accessToken: string; userID: string; login: string } & AccountCredential>(this.env, account.id, "github-copilot");
        const snapshot = await new GitHubCopilotUsageClient(this.env.transport).fetchUsage(
          account.id,
          { accessToken: credential.accessToken, userID: credential.userID, login: credential.login },
          now,
        );
        return { snapshot };
      }
      case "minimax": {
        const credential = await loadTypedCredential<{ kind: "api-key"; apiKey: string } & AccountCredential>(this.env, account.id, "api-key");
        const snapshot = await new MiniMaxUsageClient(this.env.transport).fetchUsage(account.id, credential.apiKey, now);
        return { snapshot };
      }
      case "factory": {
        const credential = await loadTypedCredential<{ kind: "api-key"; apiKey: string } & AccountCredential>(this.env, account.id, "api-key");
        const snapshot = await new FactoryUsageClient(this.env.transport).fetchUsage(account.id, credential.apiKey, now);
        return { snapshot };
      }
      case "zai": {
        const credential = await loadTypedCredential<{ kind: "api-key"; apiKey: string } & AccountCredential>(this.env, account.id, "api-key");
        const snapshot = await new ZaiUsageClient(this.env.transport).fetchUsage(account.id, credential.apiKey, now);
        return { snapshot };
      }
      case "mimo":
        return this.fetchMiMo(account, now);
      case "opencode-go":
        return this.fetchOpenCode(account, now, "go");
      case "opencode-zen":
        return this.fetchOpenCode(account, now, "billing");
      case "supergrok":
        return this.fetchSuperGrok(account, now);
      case "antigravity":
        throw ProviderClientError.credentialMismatch();
    }
  }

  private async fetchClaude(account: SubscriptionAccount, now: Date): Promise<FetchResult> {
    // Try the web-session path first when the account has a partition.
    if (account.sessionPartition && account.claudeOrganizationID) {
      const cookies = await this.env.cookieSource(account.sessionPartition);
      const selected = cookies ? claudeAPICookies(cookies) : null;
      if (selected) {
        const snapshot = await new ClaudeWebUsageClient(this.env.transport).fetchUsage(
          account.id,
          account.claudeOrganizationID,
          selected,
          now,
        );
        return { snapshot };
      }
      // Fall through to the token path if one is stored.
    }
    const credential = await loadTypedCredential<{ kind: "claude-token"; token: string } & AccountCredential>(this.env, account.id, "claude-token");
    const snapshot = await new ClaudeUsageClient(this.env.transport).fetchUsage(
      account.id,
      credential.token,
      now,
    );
    return { snapshot };
  }

  private async fetchCodex(account: SubscriptionAccount, now: Date): Promise<FetchResult> {
    const credential = await loadTypedCredential<{ kind: "codex"; oauth: OAuthCredential } & AccountCredential>(this.env, account.id, "codex");
    // The macOS app wires no credential refresh for Codex; an expired token
    // surfaces as reauthenticationRequired.
    const snapshot = await new CodexUsageClient(this.env.transport).fetchUsage(
      account.id,
      credential.oauth,
      now,
    );
    return { snapshot };
  }

  private async fetchKimi(account: SubscriptionAccount, now: Date): Promise<FetchResult> {
    const credential = await loadTypedCredential<{ kind: "kimi"; oauth: OAuthCredential } & AccountCredential>(this.env, account.id, "kimi");
    const flow = new KimiOAuthFlow(
      this.env.kimiDevice(account.id),
      this.env.transport,
      async () => true,
    );

    const refresh = async (current: OAuthCredential): Promise<OAuthCredential> => {
      return flow.refresh(current);
    };

    let oauth = credential.oauth;
    let didRefresh = false;
    if (oauthCredentialIsExpired(credential, now)) {
      oauth = await this.refreshKimi(account.id, refresh, oauth);
      didRefresh = true;
    }
    try {
      const snapshot = await new KimiUsageClient(this.env.transport).fetchUsage(account.id, oauth, now);
      return didRefresh
        ? { snapshot, updatedCredential: { kind: "kimi", oauth } }
        : { snapshot };
    } catch (error) {
      if (!isProviderClientError(error, "reauthenticationRequired") || didRefresh) {
        throw error;
      }
      oauth = await this.refreshKimi(account.id, refresh, oauth);
      const snapshot = await new KimiUsageClient(this.env.transport).fetchUsage(account.id, oauth, now);
      return { snapshot, updatedCredential: { kind: "kimi", oauth } };
    }
  }

  private async refreshKimi(
    accountID: string,
    refresh: (current: OAuthCredential) => Promise<OAuthCredential>,
    current: OAuthCredential,
  ): Promise<OAuthCredential> {
    const refreshed = await refresh(current);
    const credential: AccountCredential = { kind: "kimi", oauth: refreshed };
    await saveCredential(this.env.credentialStore, credential, accountID);
    return refreshed;
  }

  private async fetchMiMo(account: SubscriptionAccount, now: Date): Promise<FetchResult> {
    // Prefer a fresh cookie header from the live session partition (port of
    // MiMoWebAccountUsageClient), falling back to the stored header.
    if (account.sessionPartition) {
      const cookies = await this.env.cookieSource(account.sessionPartition);
      const header = cookies ? mimoCookieHeader(cookies, now) : null;
      if (header) {
        const snapshot = await new MiMoUsageClient(this.env.noRedirectTransport).fetchUsage(
          account.id,
          header,
          now,
        );
        return header !== (await this.storedMiMoHeader(account.id))
          ? { snapshot, updatedCredential: { kind: "mimo-web", cookieHeader: header } }
          : { snapshot };
      }
    }
    const credential = await loadTypedCredential<{ kind: "mimo-web"; cookieHeader: string } & AccountCredential>(this.env, account.id, "mimo-web");
    const snapshot = await new MiMoUsageClient(this.env.noRedirectTransport).fetchUsage(
      account.id,
      credential.cookieHeader,
      now,
    );
    return { snapshot };
  }

  private async storedMiMoHeader(accountID: string): Promise<string | null> {
    try {
      const stored = await loadCredential<AccountCredential>(this.env.credentialStore, accountID);
      return stored?.kind === "mimo-web" ? stored.cookieHeader : null;
    } catch {
      return null;
    }
  }

  private async fetchOpenCode(
    account: SubscriptionAccount,
    now: Date,
    page: "go" | "billing",
  ): Promise<FetchResult> {
    const credential = await loadTypedCredential<{ kind: "opencode"; workspaceID: string; authCookie: string } & AccountCredential>(this.env, account.id, "opencode");
    const client = new OpenCodeDashboardUsageClient(
      page,
      page === "go" ? decodeOpenCodeGoUsage : decodeOpenCodeZenUsage,
      this.env.noRedirectTransport,
    );

    // Prefer the live auth cookie from the session partition when present.
    let authCookie = credential.authCookie;
    let freshCookie: string | null = null;
    if (account.sessionPartition) {
      const cookies = await this.env.cookieSource(account.sessionPartition);
      freshCookie = cookies ? openCodeAuthCookie(cookies) : null;
      if (freshCookie) authCookie = freshCookie;
    }
    const snapshot = await client.fetchUsage(
      account.id,
      { workspaceID: credential.workspaceID, authCookie },
      now,
    );
    return freshCookie && freshCookie !== credential.authCookie
      ? { snapshot, updatedCredential: { kind: "opencode", workspaceID: credential.workspaceID, authCookie: freshCookie } }
      : { snapshot };
  }

  private async fetchSuperGrok(account: SubscriptionAccount, now: Date): Promise<FetchResult> {
    const credential = await loadTypedCredential<{ kind: "supergrok" } & SuperGrokCredential & AccountCredential>(this.env, account.id, "supergrok");
    const client = new SuperGrokUsageClient(this.env.transport, this.env.noRedirectTransport);
    const result = await client.fetchUsage(account.id, credential, now);
    if (result.credential !== credential) {
      return {
        snapshot: result.snapshot,
        updatedCredential: { kind: "supergrok", ...result.credential },
      };
    }
    return { snapshot: result.snapshot };
  }
}
