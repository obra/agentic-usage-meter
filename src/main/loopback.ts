// Loopback OAuth callback server — port of LoopbackOAuthCallbackServer.swift
// and OAuthCallbackParser.swift using node's http server.

import { createServer, type Server } from "node:http";
import type { LoopbackServerHandle } from "../core/providers/codex.js";

export const DEFAULT_CALLBACK_PORTS = [1455, 1457];

export class LoopbackError extends Error {
  constructor(message: "unable-to-bind" | "cancelled") {
    super(message);
    this.name = "LoopbackError";
  }
}

export async function startLoopbackServer(
  expectedState: string,
  preferredPorts: number[] = DEFAULT_CALLBACK_PORTS,
): Promise<LoopbackServerHandle> {
  for (const port of preferredPorts) {
    const handle = await tryBind(port, expectedState);
    if (handle) return handle;
  }
  throw new LoopbackError("unable-to-bind");
}

function tryBind(port: number, expectedState: string): Promise<LoopbackServerHandle | null> {
  return new Promise((resolve) => {
    let settled = false;
    let codeWaiter: ((code: string) => void) | null = null;
    let codeError: ((error: Error) => void) | null = null;
    let result: { code: string } | { error: Error } | null = null;

    const server: Server = createServer((request, response) => {
      const fail = () => {
        response.writeHead(400, { "Content-Type": "text/plain; charset=utf-8" });
        response.end("Invalid OAuth callback.");
      };
      if (request.method !== "GET" || !request.url) {
        fail();
        return;
      }
      let url: URL;
      try {
        url = new URL(request.url, `http://localhost:${port}`);
      } catch {
        fail();
        return;
      }
      if (url.pathname !== "/auth/callback") {
        fail();
        return;
      }
      const state = url.searchParams.get("state");
      const code = url.searchParams.get("code");
      if (!state || state !== expectedState || !code) {
        fail();
        return;
      }
      response.writeHead(200, { "Content-Type": "text/plain; charset=utf-8" });
      response.end("Authorization complete. You can close this window.");
      result = { code };
      codeWaiter?.(code);
      server.close();
    });

    server.on("error", () => {
      if (!settled) {
        settled = true;
        resolve(null);
      } else {
        result = { error: new LoopbackError("cancelled") };
        codeError?.(new LoopbackError("cancelled"));
      }
    });

    server.listen(port, "127.0.0.1", () => {
      settled = true;
      resolve({
        callbackURL: `http://localhost:${port}/auth/callback`,
        waitForCode: () =>
          new Promise<string>((resolveCode, rejectCode) => {
            if (result) {
              if ("code" in result) resolveCode(result.code);
              else rejectCode(result.error);
              return;
            }
            codeWaiter = resolveCode;
            codeError = rejectCode;
          }),
        cancel: () => {
          if (!result) {
            result = { error: new LoopbackError("cancelled") };
            codeError?.(new LoopbackError("cancelled"));
          }
          server.close();
        },
      });
    });
  });
}
