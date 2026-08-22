import { describe, expect, it } from "vitest";
import {
  InMemoryCredentialStore,
  loadCredential,
  saveCredential,
} from "../src/core/credentials.js";
import { oauthCredentialIsExpired, type AccountCredential } from "../src/core/models.js";

describe("InMemoryCredentialStore", () => {
  it("round-trips raw bytes per account", async () => {
    const store = new InMemoryCredentialStore();
    const bytes = new TextEncoder().encode("secret");
    await store.saveData(bytes, "a");
    expect(await store.loadData("a")).toEqual(bytes);
    expect(await store.loadData("missing")).toBeNull();
  });

  it("overwrites and deletes", async () => {
    const store = new InMemoryCredentialStore();
    await store.saveData(new TextEncoder().encode("one"), "a");
    await store.saveData(new TextEncoder().encode("two"), "a");
    expect(new TextDecoder().decode((await store.loadData("a"))!)).toBe("two");
    await store.delete("a");
    expect(await store.loadData("a")).toBeNull();
  });
});

describe("saveCredential / loadCredential", () => {
  it("round-trips a JSON credential", async () => {
    const store = new InMemoryCredentialStore();
    const credential: AccountCredential = {
      kind: "codex",
      oauth: {
        accessToken: "at",
        refreshToken: "rt",
        expiresAt: "2026-08-01T00:00:00Z",
      },
    };
    await saveCredential(store, credential, "acct-1");
    const loaded = await loadCredential<AccountCredential>(store, "acct-1");
    expect(loaded).toEqual(credential);
  });

  it("returns null for unknown accounts", async () => {
    const store = new InMemoryCredentialStore();
    expect(await loadCredential(store, "nope")).toBeNull();
  });
});

describe("oauthCredentialIsExpired", () => {
  const NOW = new Date("2026-07-29T18:00:00Z");

  it("codex/kimi credentials expire at their expiresAt instant", () => {
    const expired: AccountCredential = {
      kind: "codex",
      oauth: { accessToken: "a", expiresAt: "2026-07-29T17:59:59Z" },
    };
    const live: AccountCredential = {
      kind: "kimi",
      oauth: { accessToken: "a", expiresAt: "2026-07-29T18:00:01Z" },
    };
    expect(oauthCredentialIsExpired(expired, NOW)).toBe(true);
    expect(oauthCredentialIsExpired(live, NOW)).toBe(false);
  });

  it("missing expiresAt never expires", () => {
    const credential: AccountCredential = { kind: "codex", oauth: { accessToken: "a" } };
    expect(oauthCredentialIsExpired(credential, NOW)).toBe(false);
  });

  it("non-OAuth credential kinds never expire", () => {
    const credential: AccountCredential = { kind: "claude-token", token: "sk-ant" };
    expect(oauthCredentialIsExpired(credential, NOW)).toBe(false);
  });
});
