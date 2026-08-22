// Date / encoding helpers shared by the provider decoders.

// ISO-8601 with or without fractional seconds (matches the pair of
// ISO8601DateFormatter configurations used throughout the Swift code).
export function parseISO8601(value: string): Date | null {
  const trimmed = value.trim();
  if (!trimmed) return null;
  const ms = Date.parse(trimmed);
  return Number.isNaN(ms) ? null : new Date(ms);
}

// "yyyy-MM-dd" interpreted as UTC midnight (GitHub decoder fallback).
export function parseUTCDateOnly(value: string): Date | null {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(value.trim());
  if (!match) return null;
  const [, y, m, d] = match;
  return new Date(Date.UTC(Number(y), Number(m) - 1, Number(d)));
}

// Kimi's reset timestamps can carry >3 fractional digits; JS keeps only
// milliseconds. Port of KimiUsageResponse.Detail.resetAt(relativeTo:).
export function parseKimiResetDate(value: string, fetchedAt: Date): Date | null {
  const dot = value.indexOf(".");
  if (dot >= 0) {
    const tail = value.slice(dot + 1);
    const zoneMatch = /[Z+-]/.exec(tail);
    if (zoneMatch) {
      const fractionDigits = tail.slice(0, zoneMatch.index);
      const zone = tail.slice(zoneMatch.index);
      const fraction = Number(`0.${fractionDigits.slice(0, 6)}`);
      const whole = Date.parse(value.slice(0, dot) + zone);
      if (Number.isFinite(fraction) && !Number.isNaN(whole)) {
        return new Date(whole + fraction * 1000);
      }
    }
  }
  const plain = Date.parse(value);
  if (!Number.isNaN(plain)) return new Date(plain);
  return null;
}

export function parseKimiResetIn(resetIn: number | undefined, fetchedAt: Date): Date | null {
  if (resetIn === undefined || !Number.isFinite(resetIn) || resetIn < 0) return null;
  return new Date(fetchedAt.getTime() + resetIn * 1000);
}

// One calendar month before `date`, in UTC (Gregorian), matching the
// Calendar(identifier: .gregorian) UTC arithmetic in the Swift decoders.
export function oneMonthBeforeUTC(date: Date): Date {
  const result = new Date(date.getTime());
  result.setUTCMonth(result.getUTCMonth() - 1);
  return result;
}

export function monthIntervalUTC(date: Date): { start: Date; end: Date } {
  const start = new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), 1));
  const end = new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth() + 1, 1));
  return { start, end };
}

// "EEE h:mm a" in the given (default: local) time zone, e.g. "Wed 4:23 PM".
export function formatDayTime(date: Date, timeZone?: string): string {
  const formatter = new Intl.DateTimeFormat("en-US", {
    weekday: "short",
    hour: "numeric",
    minute: "2-digit",
    hour12: true,
    ...(timeZone ? { timeZone } : {}),
  });
  return formatter.format(date);
}

export function hexOfUTF8(value: string): string {
  return Array.from(new TextEncoder().encode(value))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

export function base64URLEncode(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

export function base64URLDecode(value: string): Uint8Array | null {
  let encoded = value.replace(/-/g, "+").replace(/_/g, "/");
  const remainder = encoded.length % 4;
  if (remainder !== 0) encoded += "=".repeat(4 - remainder);
  try {
    const binary = atob(encoded);
    const bytes = new Uint8Array(binary.length);
    for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
    return bytes;
  } catch {
    return null;
  }
}

// Decodes the payload segment of a JWT without verifying the signature —
// display metadata only, exactly as JWTMetadataDecoder in the Swift app.
export function decodeJWTPayload(token: string): Record<string, unknown> | null {
  const parts = token.split(".");
  if (parts.length !== 3 || parts.some((part) => part.length === 0)) return null;
  const payload = base64URLDecode(parts[1]!);
  if (!payload) return null;
  try {
    return JSON.parse(new TextDecoder().decode(payload)) as Record<string, unknown>;
  } catch {
    return null;
  }
}

export function flexibleNumber(value: unknown): number | undefined {
  if (typeof value === "number" && Number.isFinite(value)) return value;
  if (typeof value === "string") {
    const parsed = Number(value);
    if (value.trim() !== "" && Number.isFinite(parsed)) return parsed;
  }
  return undefined;
}

export function flexibleString(value: unknown): string | undefined {
  if (typeof value === "string") return value;
  if (typeof value === "number" && Number.isInteger(value)) return String(value);
  return undefined;
}

export function nonEmptyTrimmed(value: unknown): string | undefined {
  if (typeof value !== "string") return undefined;
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : undefined;
}
