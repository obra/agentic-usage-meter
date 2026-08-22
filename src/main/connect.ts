// Connection flows — orchestrates provider authentication from the settings
// UI. Ports the macOS connection models (Codex/Kimi/GitHub/SuperGrok device
// flows, Claude/OpenCode/MiMo embedded-web sessions, API-key entry).

import { randomUUID } from "node:crypto";
import { spawn } from "node:child_process";
import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, delimiter } from "node:path";
import { shell } from "electron";

import type { AccountCredential, Provider, SubscriptionAccount } from "../core/models.js";
import { ProviderClientError, isProviderClientError } from "../core/errors.js";
import { FetchHTTPTransport } from "../core/http.js";
import { generateOAuthState, generatePKCE } from "../core/auth/pkce.js";
import {
  CodexOAuthFlow,
  CodexUsageClient,
  type CodexOAuthResult,
} from "../core/providers/codex.js";
import { KimiOAuthFlow } from "../core/providers/kimi.js";
import { GitHubCopilotOAuthFlow } from "../core/providers/github.js";
import { ClaudeUsageClient, ClaudeWebUsageClient, claudeAPICookies, type ClaudeOrganization, type SessionCookie } from "../core/providers/claude.js";
import { MiMoUsageClient, mimoCookieHeader } from "../core/providers/mimo.js";
import {
  OpenCodeDashboardUsageClient,
  decodeOpenCodeGoUsage,
  decodeOpenCodeZenUsage,
  openCodeAuthCookie,
  openCodeWorkspaceID,
} from "../core/providers/opencode.js";
import {
  SuperGrokDeviceAuthOutputParser,
  decodeSuperGrokAuthDocument,
} from "../core/providers/supergrok.js";
import type { ConnectEvent, ConnectRequest } from "../shared/ipc.js";
import type { AppModel } from "./appModel.js";
import { kimiDeviceForAccount } from "./appModel.js";
import { startLoopbackServer } from "./loopback.js";

// The login-window surface connect flows need from the window manager.
export interface LoginWindowHandle {
  partition: string;
  close(): void;
  onCookiesChanged(cb: () => void): void;
  onNavigated(cb: (url: string) => void): void;
  cookies(url: string): Promise<SessionCookie[]>;
}

export type LoginWindowOpener = (input: {
  partition: string;
  url: string;
  title: string;
}) => Promise<LoginWindowHandle>;

export interface ConnectContext {
  appModel: AppModel;
  flowID: string;
  openLoginWindow: LoginWindowOpener;
  clearPartitionData(partition: string): Promise<void>;
  emit(event: ConnectEvent): void;
  isCancelled(): boolean;
}

const transport = new FetchHTTPTransport(true);
const noRedirectTransport = new FetchHTTPTransport(false);

const openBrowser = async (url: string): Promise<boolean> => {
  try {
    await shell.openExternal(url);
    return true;
  } catch {
    return false;
  }
};

function providerDisplayName(provider: Provider, fallback?: string): string {
  const trimmed = fallback?.trim();
  return trimmed ? trimmed : defaultAccountName(provider);
}

function defaultAccountName(provider: Provider): string {
  switch (provider) {
    case "github-copilot":
      return "GitHub";
    case "opencode-go":
      return "OpenCode Go";
    case "opencode-zen":
      return "OpenCode Zen";
    case "zai":
      return "Z.ai";
    default:
      return provider.charAt(0).toUpperCase() + provider.slice(1);
  }
}

function nextDisplayOrder(ctx: ConnectContext, provider: Provider): number {
  const existing = ctx.appModel.accounts.filter(
    (state) => state.account.provider === provider,
  );
  return existing.length;
}

async function finishAccount(
  ctx: ConnectContext,
  request: ConnectRequest,
  account: Omit<SubscriptionAccount, "id"> & { id?: string },
  credential: AccountCredential | null,
): Promise<string> {
  if (request.reconnectAccountID) {
    await ctx.appModel.reconnectAccount(request.reconnectAccountID, credential);
    return request.reconnectAccountID;
  }
  const created = await ctx.appModel.addAccount(account, credential);
  return created.id;
}

function failureMessage(error: unknown, provider: string): string {
  if (isProviderClientError(error)) {
    switch (error.kind) {
      case "credentialMismatch":
        return `${provider} returned credentials that do not match this connection.`;
      case "subscriptionRequired":
        return `The selected ${provider} subscription is not active.`;
      case "unsupportedResponse":
        return `${provider} returned a response this app does not understand.`;
      case "reauthenticationRequired":
        return `${provider} rejected the credentials. Check the sign-in and try again.`;
      case "retryAfter":
        return `${provider} rate limited the request. Try again later.`;
      case "temporaryFailure":
        return `${provider} encountered a temporary network or provider failure.`;
    }
  }
  if (error instanceof Error && error.message === "browser-open-failed") {
    return "The system browser could not be opened.";
  }
  if (error instanceof Error && error.message === "cancelled") {
    return "The connection was cancelled.";
  }
  return `${provider} connection failed.`;
}

export async function runConnectFlow(
  ctx: ConnectContext,
  request: ConnectRequest,
): Promise<void> {
  try {
    const accountIDs = await runConnectFlowInner(ctx, request);
    ctx.emit({ type: "complete", accountIDs });
  } catch (error) {
    if (error instanceof Error && error.message === "cancelled") {
      ctx.emit({ type: "failed", message: "The connection was cancelled." });
      return;
    }
    console.error("connect flow failed", error);
    ctx.emit({
      type: "failed",
      message: failureMessage(error, defaultAccountName(request.provider)),
    });
  }
}

async function runConnectFlowInner(
  ctx: ConnectContext,
  request: ConnectRequest,
): Promise<string[]> {
  switch (request.provider) {
    case "minimax":
    case "factory":
    case "zai":
      return [await connectAPIKey(ctx, request)];
    case "claude":
      if (request.method === "claudeToken") {
        return [await connectClaudeToken(ctx, request)];
      }
      return connectClaudeWeb(ctx, request);
    case "codex":
      return [await connectCodex(ctx, request)];
    case "kimi":
      return [await connectKimi(ctx, request)];
    case "github-copilot":
      return [await connectGitHub(ctx, request)];
    case "supergrok":
      return [await connectSuperGrok(ctx, request)];
    case "opencode-go":
    case "opencode-zen":
      return [await connectOpenCode(ctx, request)];
    case "mimo":
      return [await connectMiMo(ctx, request)];
    case "antigravity":
      throw new Error("Antigravity is not available on this platform.");
  }
}

// ---------------------------------------------------------------------------
// API key providers
// ---------------------------------------------------------------------------

async function connectAPIKey(ctx: ConnectContext, request: ConnectRequest): Promise<string> {
  const apiKey = request.apiKey?.trim() ?? "";
  if (!apiKey) throw ProviderClientError.credentialMismatch();

  // Validate the key against the live provider before saving.
  const probeID = randomUUID();
  const now = new Date();
  switch (request.provider) {
    case "minimax": {
      const { MiniMaxUsageClient } = await import("../core/providers/minimax.js");
      await new MiniMaxUsageClient(transport).fetchUsage(probeID, apiKey, now);
      break;
    }
    case "factory": {
      const { FactoryUsageClient } = await import("../core/providers/factory.js");
      await new FactoryUsageClient(transport).fetchUsage(probeID, apiKey, now);
      break;
    }
    default: {
      const { ZaiUsageClient } = await import("../core/providers/zai.js");
      await new ZaiUsageClient(transport).fetchUsage(probeID, apiKey, now);
      break;
    }
  }

  return finishAccount(
    ctx,
    request,
    {
      provider: request.provider,
      displayName: providerDisplayName(request.provider, request.displayName),
      displayOrder: nextDisplayOrder(ctx, request.provider),
    },
    { kind: "api-key", apiKey },
  );
}

// ---------------------------------------------------------------------------
// Claude via setup token
// ---------------------------------------------------------------------------

async function connectClaudeToken(ctx: ConnectContext, request: ConnectRequest): Promise<string> {
  const token = request.token?.trim() ?? "";
  if (!token) throw ProviderClientError.credentialMismatch();
  const probeID = randomUUID();
  const snapshot = await new ClaudeUsageClient(transport).fetchUsage(probeID, token, new Date());
  void snapshot; // reaching here means the token works
  return finishAccount(
    ctx,
    request,
    {
      provider: "claude",
      displayName: providerDisplayName("claude", request.displayName),
      displayOrder: nextDisplayOrder(ctx, "claude"),
    },
    { kind: "claude-token", token },
  );
}

// ---------------------------------------------------------------------------
// Codex browser OAuth
// ---------------------------------------------------------------------------

async function connectCodex(ctx: ConnectContext, request: ConnectRequest): Promise<string> {
  const flow = new CodexOAuthFlow(transport, openBrowser, (expectedState) =>
    startLoopbackServer(expectedState),
  );
  ctx.emit({ type: "status", message: "Opening ChatGPT sign-in in your browser…" });
  const result: CodexOAuthResult = await flow.authenticate({
    pkce: generatePKCE,
    state: generateOAuthState,
  });
  if (!result.credential.accountID) {
    throw ProviderClientError.unsupportedResponse();
  }
  const displayName =
    providerDisplayName("codex", request.displayName) !== defaultAccountName("codex")
      ? providerDisplayName("codex", request.displayName)
      : result.identity.email ?? defaultAccountName("codex");
  return finishAccount(
    ctx,
    request,
    {
      provider: "codex",
      displayName,
      displayOrder: nextDisplayOrder(ctx, "codex"),
      ...(result.identity.email ? { authenticatedIdentity: result.identity.email } : {}),
    },
    { kind: "codex", oauth: result.credential },
  );
}

// ---------------------------------------------------------------------------
// Kimi device authorization
// ---------------------------------------------------------------------------

async function connectKimi(ctx: ConnectContext, request: ConnectRequest): Promise<string> {
  const accountID = request.reconnectAccountID ?? randomUUID();
  const flow = new KimiOAuthFlow(
    kimiDeviceForAccount(accountID),
    transport,
    openBrowser,
  );
  const oauth = await flow.authenticate((prompt) => {
    ctx.emit({
      type: "prompt",
      verificationURL: prompt.verificationURL,
      userCode: prompt.userCode,
      expiresAt: prompt.expiresAt.toISOString(),
    });
  });
  return finishAccount(
    ctx,
    request,
    {
      id: accountID,
      provider: "kimi",
      displayName: providerDisplayName("kimi", request.displayName),
      displayOrder: nextDisplayOrder(ctx, "kimi"),
    },
    { kind: "kimi", oauth },
  );
}

// ---------------------------------------------------------------------------
// GitHub device OAuth
// ---------------------------------------------------------------------------

async function connectGitHub(ctx: ConnectContext, request: ConnectRequest): Promise<string> {
  const flow = new GitHubCopilotOAuthFlow(transport, openBrowser);
  const credential = await flow.authenticate((prompt) => {
    ctx.emit({
      type: "prompt",
      verificationURL: prompt.verificationURL,
      userCode: prompt.userCode,
      expiresAt: prompt.expiresAt.toISOString(),
    });
  });
  return finishAccount(
    ctx,
    request,
    {
      provider: "github-copilot",
      displayName:
        request.displayName?.trim() || credential.login,
      authenticatedIdentity: credential.login,
      displayOrder: nextDisplayOrder(ctx, "github-copilot"),
    },
    {
      kind: "github-copilot",
      accessToken: credential.accessToken,
      userID: credential.userID,
      login: credential.login,
    },
  );
}

// ---------------------------------------------------------------------------
// SuperGrok CLI device authentication
// ---------------------------------------------------------------------------

function locateExecutable(name: string): string | null {
  const pathEnv = process.env.PATH ?? "";
  const extensions =
    process.platform === "win32"
      ? (process.env.PATHEXT ?? ".EXE;.CMD;.BAT;.COM").split(";")
      : [""];
  for (const directory of pathEnv.split(delimiter)) {
    if (!directory) continue;
    for (const extension of extensions) {
      const candidate = join(directory, name + extension.toLowerCase());
      try {
        readFileSync(candidate);
        return candidate;
      } catch {
        // keep searching
      }
      const upper = join(directory, name + extension);
      try {
        readFileSync(upper);
        return upper;
      } catch {
        // keep searching
      }
    }
  }
  return null;
}

async function connectSuperGrok(ctx: ConnectContext, request: ConnectRequest): Promise<string> {
  const executable = locateExecutable("grok");
  if (!executable) {
    throw new Error(
      "The grok CLI was not found on PATH. Install it (npm install -g @vibe/grok or x.ai instructions) and try again.",
    );
  }

  const profileDirectory = mkdtempSync(join(tmpdir(), "AgenticUsageMeter-Grok-"));
  const parser = new SuperGrokDeviceAuthOutputParser();
  let lastPrompt: { verificationURL: string; userCode: string } | null = null;

  try {
    const env: NodeJS.ProcessEnv = { ...process.env, GROK_HOME: profileDirectory };
    delete env["GROK_AUTH_FILE"];
    delete env["GROK_ACCESS_TOKEN"];
    delete env["XAI_API_KEY"];

    ctx.emit({ type: "status", message: "Starting grok login --device-auth…" });
    const status = await new Promise<number>((resolve, reject) => {
      const child = spawn(executable, ["login", "--device-auth"], { env });
      child.stdout.on("data", (chunk: Buffer) => {
        const prompt = parser.append(chunk.toString("utf-8"));
        if (prompt && prompt.userCode !== lastPrompt?.userCode) {
          lastPrompt = prompt;
          ctx.emit({
            type: "prompt",
            verificationURL: prompt.verificationURL,
            userCode: prompt.userCode,
          });
          void openBrowser(prompt.verificationURL);
        }
      });
      child.stderr.on("data", (chunk: Buffer) => {
        parser.append(chunk.toString("utf-8"));
      });
      child.on("error", reject);
      child.on("close", (code) => resolve(code ?? 1));
    });
    if (ctx.isCancelled()) throw new Error("cancelled");
    if (status !== 0) {
      throw ProviderClientError.reauthenticationRequired();
    }

    const authFile = join(profileDirectory, "auth.json");
    const credential = decodeSuperGrokAuthDocument(
      new Uint8Array(readFileSync(authFile)),
    );
    return finishAccount(
      ctx,
      request,
      {
        provider: "supergrok",
        displayName:
          request.displayName?.trim() || credential.email || defaultAccountName("supergrok"),
        ...(credential.email ? { authenticatedIdentity: credential.email } : {}),
        displayOrder: nextDisplayOrder(ctx, "supergrok"),
      },
      { kind: "supergrok", ...credential },
    );
  } finally {
    try {
      rmSync(profileDirectory, { recursive: true, force: true });
    } catch {
      // best effort cleanup
    }
  }
}

// ---------------------------------------------------------------------------
// Embedded-web-session providers (Claude / OpenCode / MiMo)
// ---------------------------------------------------------------------------

async function connectClaudeWeb(ctx: ConnectContext, request: ConnectRequest): Promise<string[]> {
  const partition = `persist:account-${randomUUID()}`;
  const window = await ctx.openLoginWindow({
    partition,
    url: "https://claude.ai/login",
    title: "Sign In to Claude",
  });
  try {
    ctx.emit({ type: "status", message: "Sign in to Claude in the opened window…" });
    const cookies = await waitForCookies(
      window,
      (all) => claudeAPICookies(all),
      () => ctx.isCancelled(),
    );
    const client = new ClaudeWebUsageClient(transport);
    const organizations = await client.organizations(cookies);
    ctx.emit({ type: "claude-organizations", organizations });
    // The renderer answers via selectClaudeOrganizations below.
    const selected = await waitForClaudeSelection(ctx, organizations);
    const accountIDs: string[] = [];
    for (const organization of selected) {
      const accountID = await finishAccount(
        ctx,
        request,
        {
          provider: "claude",
          displayName:
            selected.length === 1
              ? providerDisplayName("claude", request.displayName)
              : organization.name,
          authenticatedIdentity: organization.name,
          displayOrder: nextDisplayOrder(ctx, "claude") + accountIDs.length,
          claudeOrganizationID: organization.uuid,
          sessionPartition: partition,
        },
        { kind: "claude-web" },
      );
      accountIDs.push(accountID);
    }
    return accountIDs;
  } finally {
    window.close();
  }
}

// Registered per in-flight Claude web connect; resolved by the
// connectClaudeOrgs IPC call from the settings renderer.
const pendingClaudeSelections = new Map<
  string,
  (organizationIDs: string[]) => void
>();

export function resolveClaudeSelection(flowID: string, organizationIDs: string[]): boolean {
  const resolver = pendingClaudeSelections.get(flowID);
  if (!resolver) return false;
  pendingClaudeSelections.delete(flowID);
  resolver(organizationIDs);
  return true;
}

export function cancelClaudeSelection(flowID: string): void {
  pendingClaudeSelections.delete(flowID);
}

function waitForClaudeSelection(
  ctx: ConnectContext & { flowID: string },
  organizations: ClaudeOrganization[],
): Promise<ClaudeOrganization[]> {
  return new Promise((resolve, reject) => {
    pendingClaudeSelections.set(ctx.flowID, (ids) => {
      const selected = organizations.filter((org) => ids.includes(org.uuid));
      resolve(selected.length > 0 ? selected : organizations.slice(0, 1));
    });
    const poll = () => {
      if (ctx.isCancelled()) {
        pendingClaudeSelections.delete(ctx.flowID);
        reject(new Error("cancelled"));
        return;
      }
      if (pendingClaudeSelections.has(ctx.flowID)) {
        setTimeout(poll, 250);
      }
    };
    setTimeout(poll, 250);
  });
}

async function connectOpenCode(ctx: ConnectContext, request: ConnectRequest): Promise<string> {
  const provider = request.provider;
  const partition = `persist:account-${randomUUID()}`;
  const window = await ctx.openLoginWindow({
    partition,
    url: "https://opencode.ai/auth",
    title: `Sign In to ${provider === "opencode-go" ? "OpenCode Go" : "OpenCode Zen"}`,
  });
  try {
    ctx.emit({ type: "status", message: "Sign in to OpenCode in the opened window…" });
    let workspaceID: string | null = null;
    window.onNavigated((url) => {
      workspaceID = openCodeWorkspaceID(url) ?? workspaceID;
    });
    const authCookie = await waitForCookies(
      window,
      (all) => {
        const cookie = openCodeAuthCookie(all);
        return cookie && workspaceID ? { cookie, workspace: workspaceID } : null;
      },
      () => ctx.isCancelled(),
    );

    // Validate the session by fetching usage once.
    const client = new OpenCodeDashboardUsageClient(
      provider === "opencode-go" ? "go" : "billing",
      provider === "opencode-go" ? decodeOpenCodeGoUsage : decodeOpenCodeZenUsage,
      noRedirectTransport,
    );
    await client.fetchUsage(
      randomUUID(),
      { workspaceID: authCookie.workspace, authCookie: authCookie.cookie },
      new Date(),
    );

    return finishAccount(
      ctx,
      request,
      {
        provider,
        displayName:
          request.displayName?.trim() ||
          `${defaultAccountName(provider)} (${authCookie.workspace})`,
        displayOrder: nextDisplayOrder(ctx, provider),
        sessionPartition: partition,
      },
      { kind: "opencode", workspaceID: authCookie.workspace, authCookie: authCookie.cookie },
    );
  } finally {
    window.close();
  }
}

async function connectMiMo(ctx: ConnectContext, request: ConnectRequest): Promise<string> {
  const partition = `persist:account-${randomUUID()}`;
  const window = await ctx.openLoginWindow({
    partition,
    url: "https://platform.xiaomimimo.com/console/balance",
    title: "Sign In to MiMo",
  });
  try {
    ctx.emit({ type: "status", message: "Sign in to MiMo in the opened window…" });
    const header = await waitForCookies(
      window,
      (all) => mimoCookieHeader(all),
      () => ctx.isCancelled(),
    );
    // Validate via the token plan endpoint before saving.
    await new MiMoUsageClient(noRedirectTransport).fetchUsage(randomUUID(), header, new Date());
    return finishAccount(
      ctx,
      request,
      {
        provider: "mimo",
        displayName: providerDisplayName("mimo", request.displayName),
        displayOrder: nextDisplayOrder(ctx, "mimo"),
        sessionPartition: partition,
      },
      { kind: "mimo-web", cookieHeader: header },
    );
  } finally {
    window.close();
  }
}

// Polls the login window's cookies until the selector produces a value.
// window.cookies("") returns every cookie in the partition.
async function waitForCookies<T>(
  window: LoginWindowHandle,
  select: (cookies: SessionCookie[]) => T | null,
  isCancelled: () => boolean,
): Promise<T> {
  return new Promise<T>((resolve, reject) => {
    let inFlight = false;
    const check = async () => {
      if (isCancelled()) {
        reject(new Error("cancelled"));
        return;
      }
      if (inFlight) return;
      inFlight = true;
      try {
        // Read all cookies for the partition's domains; providers filter by
        // domain themselves.
        const cookies = await window.cookies("");
        const selected = select(cookies);
        if (selected) {
          resolve(selected);
          return;
        }
      } finally {
        inFlight = false;
      }
    };
    window.onCookiesChanged(() => void check());
    const interval = setInterval(() => {
      if (isCancelled()) {
        clearInterval(interval);
        reject(new Error("cancelled"));
        return;
      }
      void check();
    }, 500);
    void check();
  });
}
