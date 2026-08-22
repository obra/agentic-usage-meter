// PKCE + OAuth state — port of PKCE.swift and OAuthState from
// CodexOAuthRequests.swift.

import { createHash, randomBytes } from "node:crypto";
import { base64URLEncode } from "../dates.js";

export interface PKCECodes {
  verifier: string;
  challenge: string;
}

export function generatePKCE(): PKCECodes {
  const verifier = base64URLEncode(randomBytes(64));
  const challenge = base64URLEncode(createHash("sha256").update(verifier).digest());
  return { verifier, challenge };
}

export function generateOAuthState(): string {
  return base64URLEncode(randomBytes(32));
}
