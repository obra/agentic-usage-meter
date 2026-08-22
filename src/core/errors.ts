// Error types — port of ProviderClientError / RefreshFailure from
// repo/Sources/UsageMeterCore (Providers/UsageProviderClient.swift,
// Refresh/AccountRefresher.swift).

export type ProviderClientErrorKind =
  | "credentialMismatch"
  | "subscriptionRequired"
  | "unsupportedResponse"
  | "reauthenticationRequired"
  | "retryAfter"
  | "temporaryFailure";

export class ProviderClientError extends Error {
  readonly kind: ProviderClientErrorKind;
  readonly retryAt: Date | null;

  private constructor(kind: ProviderClientErrorKind, retryAt: Date | null) {
    super(kind);
    this.name = "ProviderClientError";
    this.kind = kind;
    this.retryAt = retryAt;
  }

  static credentialMismatch(): ProviderClientError {
    return new ProviderClientError("credentialMismatch", null);
  }
  static subscriptionRequired(): ProviderClientError {
    return new ProviderClientError("subscriptionRequired", null);
  }
  static unsupportedResponse(): ProviderClientError {
    return new ProviderClientError("unsupportedResponse", null);
  }
  static reauthenticationRequired(): ProviderClientError {
    return new ProviderClientError("reauthenticationRequired", null);
  }
  static retryAfter(retryAt: Date | null): ProviderClientError {
    return new ProviderClientError("retryAfter", retryAt);
  }
  static temporaryFailure(): ProviderClientError {
    return new ProviderClientError("temporaryFailure", null);
  }
}

export function isProviderClientError(
  error: unknown,
  kind?: ProviderClientErrorKind,
): error is ProviderClientError {
  return (
    error instanceof ProviderClientError && (kind === undefined || error.kind === kind)
  );
}

// Refresh failures feed AccountRefresher's outcome classification.
export type RefreshFailure =
  | { type: "authenticationRequired" }
  | { type: "transient"; providerRetryAt: Date | null };

// Maps a thrown error to a RefreshFailure when the refresher should treat it
// as a managed outcome rather than a hard failure.
export function classifyRefreshFailure(error: unknown): RefreshFailure | null {
  if (isProviderClientError(error, "reauthenticationRequired")) {
    return { type: "authenticationRequired" };
  }
  if (isProviderClientError(error, "retryAfter")) {
    return { type: "transient", providerRetryAt: error.retryAt };
  }
  if (isProviderClientError(error, "temporaryFailure")) {
    return { type: "transient", providerRetryAt: null };
  }
  return null;
}
