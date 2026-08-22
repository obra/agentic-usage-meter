// Persistence: app state JSON + safeStorage-encrypted credential file.

import { app, safeStorage } from "electron";
import { mkdirSync, readFileSync, renameSync, writeFileSync, existsSync, chmodSync } from "node:fs";
import { mkdir, readFile, rename, writeFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import type { PersistedAppState } from "../core/models.js";
import { emptyPersistedState } from "../core/models.js";
import type { CredentialStore } from "../core/credentials.js";

async function writeFileAtomic(path: string, data: string): Promise<void> {
  await mkdir(dirname(path), { recursive: true });
  const temporary = `${path}.tmp-${process.pid}`;
  await writeFile(temporary, data, { encoding: "utf-8", mode: 0o600 });
  await rename(temporary, path);
}

export class AppStateStore {
  private cached: PersistedAppState | null = null;

  constructor(private readonly filePath: string) {}

  async load(): Promise<PersistedAppState> {
    if (this.cached) return this.cached;
    try {
      const raw = await readFile(this.filePath, "utf-8");
      const parsed = JSON.parse(raw) as PersistedAppState;
      this.cached = { ...emptyPersistedState(), ...parsed };
    } catch {
      this.cached = emptyPersistedState();
    }
    return this.cached;
  }

  async save(state: PersistedAppState): Promise<void> {
    this.cached = state;
    await writeFileAtomic(this.filePath, JSON.stringify(state, null, 2));
  }
}

interface CredentialFileEntry {
  encrypted: boolean;
  data: string; // base64 of encrypted bytes, or utf8 JSON when unencrypted
}

// Port of KeychainCredentialStore using Electron safeStorage: DPAPI on
// Windows, Keychain on macOS, libsecret on Linux. When no OS encryption is
// available (rare; headless Linux), falls back to a 0600-permission file and
// marks entries unencrypted.
export class SafeStorageCredentialStore implements CredentialStore {
  private entries: Record<string, CredentialFileEntry> | null = null;
  private writing: Promise<void> = Promise.resolve();

  constructor(private readonly filePath: string) {}

  private get encryptionAvailable(): boolean {
    try {
      return safeStorage.isEncryptionAvailable();
    } catch {
      return false;
    }
  }

  private async load(): Promise<Record<string, CredentialFileEntry>> {
    if (this.entries) return this.entries;
    try {
      const raw = await readFile(this.filePath, "utf-8");
      this.entries = JSON.parse(raw) as Record<string, CredentialFileEntry>;
    } catch {
      this.entries = {};
    }
    return this.entries;
  }

  private async persist(): Promise<void> {
    const snapshot = this.entries ?? {};
    this.writing = this.writing.then(() =>
      writeFileAtomic(this.filePath, JSON.stringify(snapshot)),
    );
    await this.writing;
  }

  async saveData(data: Uint8Array, accountID: string): Promise<void> {
    const entries = await this.load();
    if (this.encryptionAvailable) {
      const encrypted = safeStorage.encryptString(new TextDecoder().decode(data));
      entries[accountID] = { encrypted: true, data: encrypted.toString("base64") };
    } else {
      entries[accountID] = {
        encrypted: false,
        data: Buffer.from(data).toString("base64"),
      };
    }
    await this.persist();
  }

  async loadData(accountID: string): Promise<Uint8Array | null> {
    const entries = await this.load();
    const entry = entries[accountID];
    if (!entry) return null;
    const buffer = Buffer.from(entry.data, "base64");
    if (!entry.encrypted) return new Uint8Array(buffer);
    try {
      const plain = safeStorage.decryptString(buffer);
      return new TextEncoder().encode(plain);
    } catch {
      return null;
    }
  }

  async delete(accountID: string): Promise<void> {
    const entries = await this.load();
    if (accountID in entries) {
      delete entries[accountID];
      await this.persist();
    }
  }
}

export function defaultDataDirectory(): string {
  return app.getPath("userData");
}

export function defaultStateFilePath(): string {
  return join(defaultDataDirectory(), "state.json");
}

export function defaultCredentialFilePath(): string {
  return join(defaultDataDirectory(), "credentials.json");
}

// Synchronous variant used by the icon-generation build script.
export function readJSONFileSync<T>(path: string): T | null {
  try {
    if (!existsSync(path)) return null;
    return JSON.parse(readFileSync(path, "utf-8")) as T;
  } catch {
    return null;
  }
}

export function writeFileSyncRestricted(path: string, data: string): void {
  mkdirSync(dirname(path), { recursive: true });
  writeFileSync(path, data, { encoding: "utf-8" });
  try {
    chmodSync(path, 0o600);
  } catch {
    // best effort on platforms without POSIX permissions
  }
}
