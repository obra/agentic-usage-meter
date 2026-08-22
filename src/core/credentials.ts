// Credential store contract — port of CredentialStore.swift. The Electron
// (safeStorage) implementation lives in src/main; this in-memory
// implementation backs unit tests.

export interface CredentialStore {
  saveData(data: Uint8Array, accountID: string): Promise<void>;
  loadData(accountID: string): Promise<Uint8Array | null>;
  delete(accountID: string): Promise<void>;
}

export async function saveCredential(
  store: CredentialStore,
  credential: unknown,
  accountID: string,
): Promise<void> {
  await store.saveData(new TextEncoder().encode(JSON.stringify(credential)), accountID);
}

export async function loadCredential<T>(
  store: CredentialStore,
  accountID: string,
): Promise<T | null> {
  const data = await store.loadData(accountID);
  if (!data) return null;
  return JSON.parse(new TextDecoder().decode(data)) as T;
}

export class InMemoryCredentialStore implements CredentialStore {
  private readonly data = new Map<string, Uint8Array>();

  async saveData(data: Uint8Array, accountID: string): Promise<void> {
    this.data.set(accountID, data);
  }

  async loadData(accountID: string): Promise<Uint8Array | null> {
    return this.data.get(accountID) ?? null;
  }

  async delete(accountID: string): Promise<void> {
    this.data.delete(accountID);
  }
}
