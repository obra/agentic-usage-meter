// HTTP transport — port of repo/Sources/UsageMeterCore/Networking/
// HTTPTransport.swift using fetch (available in both Electron main and Node).

export interface HTTPRequest {
  url: string;
  method: string;
  headers: Record<string, string>;
  body?: Uint8Array | string;
}

export class HTTPResponse {
  readonly data: Uint8Array;
  readonly statusCode: number;
  readonly headers: Record<string, string>;

  constructor(data: Uint8Array, statusCode: number, headers: Record<string, string>) {
    this.data = data;
    this.statusCode = statusCode;
    const lowered: Record<string, string> = {};
    for (const [key, value] of Object.entries(headers)) {
      lowered[key.toLowerCase()] = value;
    }
    this.headers = lowered;
  }

  header(named: string): string | undefined {
    return this.headers[named.toLowerCase()];
  }

  text(): string {
    return new TextDecoder("utf-8").decode(this.data);
  }

  json(): unknown {
    return JSON.parse(this.text());
  }

  // Port of HTTPResponse.retryDate(relativeTo:).
  retryDate(relativeTo: Date): Date | null {
    const value = this.header("Retry-After");
    if (!value) return null;
    const seconds = Number(value);
    if (Number.isFinite(seconds) && seconds >= 0 && /^\s*\d+(\.\d+)?\s*$/.test(value)) {
      return new Date(relativeTo.getTime() + seconds * 1000);
    }
    const parsed = Date.parse(value); // HTTP-date is parseable by Date.parse
    return Number.isNaN(parsed) ? null : new Date(parsed);
  }
}

export interface HTTPTransport {
  send(request: HTTPRequest): Promise<HTTPResponse>;
}

export class FetchHTTPTransport implements HTTPTransport {
  constructor(private readonly followsRedirects = true) {}

  async send(request: HTTPRequest): Promise<HTTPResponse> {
    const response = await fetch(request.url, {
      method: request.method,
      headers: request.headers,
      ...(request.body !== undefined ? { body: request.body } : {}),
      redirect: this.followsRedirects ? "follow" : "manual",
    });
    const buffer = new Uint8Array(await response.arrayBuffer());
    const headers: Record<string, string> = {};
    response.headers.forEach((value, key) => {
      headers[key] = value;
    });
    return new HTTPResponse(buffer, response.status, headers);
  }
}

export function formURLEncoded(items: [string, string][]): string {
  return items
    .map(([name, value]) => `${encodeURIComponent(name)}=${encodeURIComponent(value)}`)
    .join("&");
}
