// Settings renderer: account management + provider connection flows.

interface ProviderInfo {
  provider: string;
  displayName: string;
  connectionDetail: string;
  color: string;
  releaseState: string;
  strategy: string;
  dashboardURL: string | null;
}

interface SettingsAccount {
  account: {
    id: string;
    provider: string;
    displayName: string;
    authenticatedIdentity?: string;
  };
  providerInfo: ProviderInfo;
  error: "requiresReauthentication" | "temporarilyUnavailable" | null;
  isRefreshing: boolean;
  lastFetchedAt: string | null;
}

interface SettingsState {
  accounts: SettingsAccount[];
  providers: ProviderInfo[];
  isSampleData: boolean;
}

interface ConnectRequest {
  provider: string;
  method: "auto" | "apiKey" | "claudeToken";
  displayName?: string;
  apiKey?: string;
  token?: string;
  reconnectAccountID?: string;
}

type ConnectEvent =
  | { type: "prompt"; verificationURL: string; userCode: string; expiresAt?: string }
  | { type: "status"; message: string }
  | {
      type: "claude-organizations";
      organizations: { uuid: string; name: string; capabilities: string[] }[];
    }
  | { type: "complete"; accountIDs: string[] }
  | { type: "failed"; message: string };

interface SettingsAPI {
  getState(): Promise<{ settings: SettingsState }>;
  onState(callback: (payload: { settings: SettingsState }) => void): () => void;
  connectStart(request: ConnectRequest): Promise<string>;
  onConnectEvent(
    callback: (payload: { flowID: string; event: ConnectEvent }) => void,
  ): () => void;
  claudeSelectOrgs(flowID: string, organizationIDs: string[]): Promise<boolean>;
  connectCancel(flowID: string): Promise<void>;
  removeAccount(accountID: string): Promise<void>;
  refreshAccount(accountID: string): Promise<void>;
  openDashboard(accountID: string): Promise<void>;
}

const api = (window as unknown as { usageMeterSettings: SettingsAPI })
  .usageMeterSettings;

let activeFlowID: string | null = null;

// Two-letter badge codes (single letters collide: Claude/Codex, MiniMax/MiMo,
// OpenCode Go/Zen). All-caps monogram style.
const BADGE_TEXT: Record<string, string> = {
  claude: "CL",
  codex: "CO",
  kimi: "KI",
  "github-copilot": "GH",
  minimax: "MM",
  factory: "F",
  "opencode-go": "OG",
  "opencode-zen": "OZ",
  supergrok: "SG",
  zai: "Z",
  mimo: "MI",
};

// Plain-language sign-in method per connection strategy.
const METHOD_TEXT: Record<string, string> = {
  isolatedWebSession: "Browser sign-in",
  browserOAuth: "Browser sign-in",
  deviceOAuth: "Device code",
  apiKey: "API key",
  isolatedCLIProfile: "grok CLI",
};

const ICONS = {
  refresh:
    '<svg width="13" height="13" viewBox="0 0 16 16" fill="none"><path d="M13.5 8a5.5 5.5 0 1 1-1.61-3.89M13.5 1.5v3h-3" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/></svg>',
  external:
    '<svg width="13" height="13" viewBox="0 0 16 16" fill="none"><path d="M7 3H4a1 1 0 0 0-1 1v8a1 1 0 0 0 1 1h8a1 1 0 0 0 1-1V9M10 3h3v3M13 3 8 8" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/></svg>',
  remove:
    '<svg width="13" height="13" viewBox="0 0 16 16" fill="none"><path d="M4 4l8 8M12 4l-8 8" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"/></svg>',
};

function el(tag: string, className?: string, text?: string): HTMLElement {
  const node = document.createElement(tag);
  if (className) node.className = className;
  if (text !== undefined) node.textContent = text;
  return node;
}

function iconButton(
  svg: string,
  title: string,
  onClick: () => void,
  danger = false,
): HTMLElement {
  const button = el("button", `icon-btn${danger ? " danger" : ""}`);
  button.innerHTML = svg;
  button.title = title;
  button.setAttribute("aria-label", title);
  button.addEventListener("click", onClick);
  return button;
}

function badge(info: ProviderInfo): HTMLElement {
  const text =
    BADGE_TEXT[info.provider] ?? info.displayName.slice(0, 1).toUpperCase();
  const node = el("span", "badge", text);
  node.style.background = info.color;
  return node;
}

function relativeTime(iso: string): string {
  const seconds = Math.max(0, (Date.now() - new Date(iso).getTime()) / 1000);
  if (seconds < 60) return "just now";
  const minutes = Math.floor(seconds / 60);
  if (minutes < 60) return `${minutes}m ago`;
  const hours = Math.floor(minutes / 60);
  if (hours < 24) return `${hours}h ago`;
  return `${Math.floor(hours / 24)}d ago`;
}

// ---------------------------------------------------------------------------
// Account list
// ---------------------------------------------------------------------------

function renderAccounts(state: SettingsState): void {
  const container = document.getElementById("accounts")!;
  container.textContent = "";
  if (state.accounts.length === 0) {
    container.append(
      el("div", "empty-card", "No accounts connected yet — pick a provider below."),
    );
    return;
  }

  const sorted = [...state.accounts].sort(
    (a, b) =>
      a.providerInfo.displayName.localeCompare(b.providerInfo.displayName) ||
      a.account.displayName.localeCompare(b.account.displayName),
  );

  for (const entry of sorted) {
    const { providerInfo, account } = entry;
    const card = el("div", "account-card");
    card.append(badge(providerInfo));

    const info = el("div", "info");
    const isRedundantName = account.displayName === providerInfo.displayName;
    const name = el("div", "name", account.displayName);
    if (!isRedundantName) {
      name.append(el("span", "provider-tag", providerInfo.displayName));
    }
    info.append(name);

    const details: string[] = [];
    if (account.authenticatedIdentity) details.push(account.authenticatedIdentity);
    if (entry.lastFetchedAt) {
      details.push(`Updated ${relativeTime(entry.lastFetchedAt)}`);
    }
    if (details.length > 0) info.append(el("div", "sub", details.join(" · ")));
    card.append(info);

    // Status: colored dot + plain-language label.
    const statusKind = entry.error
      ? entry.error === "requiresReauthentication"
        ? "error"
        : "warn"
      : entry.isRefreshing
        ? "busy"
        : "ok";
    const statusText =
      statusKind === "error"
        ? "Sign-in required"
        : statusKind === "warn"
          ? "Temporarily unavailable"
          : statusKind === "busy"
            ? "Refreshing…"
            : "Connected";
    const status = el("div", `status ${statusKind}`);
    status.append(el("span", "dot"), el("span", undefined, statusText));
    card.append(status);

    const actions = el("div", "actions");
    if (entry.error === "requiresReauthentication") {
      const reconnect = el("button", "reconnect-btn", "Reconnect");
      reconnect.addEventListener("click", () =>
        selectProvider(providerInfo, account.id),
      );
      actions.append(reconnect);
    }
    actions.append(
      iconButton(ICONS.refresh, "Refresh now", () =>
        void api.refreshAccount(account.id),
      ),
    );
    if (providerInfo.dashboardURL) {
      actions.append(
        iconButton(ICONS.external, "Open usage dashboard", () =>
          void api.openDashboard(account.id),
        ),
      );
    }
    actions.append(
      iconButton(
        ICONS.remove,
        "Remove account",
        () => {
          if (confirm(`Remove ${account.displayName}?`)) {
            void api.removeAccount(account.id);
          }
        },
        true,
      ),
    );
    card.append(actions);
    container.append(card);
  }
}

// ---------------------------------------------------------------------------
// Provider picker + connect forms
// ---------------------------------------------------------------------------

function renderProviders(state: SettingsState): void {
  const container = document.getElementById("providers")!;
  container.textContent = "";
  const sorted = [...state.providers].sort((a, b) =>
    a.displayName.localeCompare(b.displayName),
  );
  for (const info of sorted) {
    const cell = el("button", "provider-cell");
    cell.append(badge(info));
    const meta = el("div", "meta");
    meta.append(el("div", "label", info.displayName));
    meta.append(
      el("div", "detail", METHOD_TEXT[info.strategy] ?? info.connectionDetail),
    );
    cell.append(meta);
    cell.append(el("span", "plus", "+"));
    cell.addEventListener("click", () => selectProvider(info));
    container.append(cell);
  }
}

function closeModal(): void {
  if (activeFlowID) void api.connectCancel(activeFlowID);
  activeFlowID = null;
  document.getElementById("modal-backdrop")!.hidden = true;
}

function openModal(): void {
  document.getElementById("modal-backdrop")!.hidden = false;
}

// Dismiss via backdrop click or Escape; both cancel any in-flight flow.
document.getElementById("modal-backdrop")!.addEventListener("click", (event) => {
  if (event.target === event.currentTarget) closeModal();
});
document.addEventListener("keydown", (event) => {
  if (
    event.key === "Escape" &&
    !document.getElementById("modal-backdrop")!.hidden
  ) {
    closeModal();
  }
});

function selectProvider(info: ProviderInfo, reconnectAccountID?: string): void {
  const form = document.getElementById("connect-form")!;
  document.getElementById("connect-progress")!.hidden = true;
  form.hidden = false;
  form.textContent = "";

  const head = el("div", "form-head");
  head.append(
    el(
      "h3",
      undefined,
      `${reconnectAccountID ? "Reconnect" : "Connect"} ${info.displayName}`,
    ),
  );
  const close = el("button", "close-btn");
  close.innerHTML = ICONS.remove;
  close.title = "Close";
  close.setAttribute("aria-label", "Close");
  close.addEventListener("click", closeModal);
  head.append(close);
  form.append(head);
  form.append(el("p", "hint", info.connectionDetail));
  openModal();

  const nameInput = document.createElement("input");
  nameInput.placeholder = "e.g. Work, Personal";
  // Reconnecting keeps the existing account (and its name) — only ask for a
  // name on a fresh connection.
  const nameField = () => {
    if (!reconnectAccountID) {
      form.append(field("Account name (optional)", nameInput));
    }
  };

  const start = (request: Partial<ConnectRequest>) => {
    const displayName = nameInput.value.trim();
    beginFlow(
      {
        provider: info.provider,
        method: "auto",
        ...(displayName ? { displayName } : {}),
        ...(reconnectAccountID ? { reconnectAccountID } : {}),
        ...request,
      } as ConnectRequest,
    );
  };

  const buttonRow = (...buttons: HTMLElement[]) => {
    const row = el("div", "button-row");
    const cancel = el("button", "btn ghost", "Cancel");
    cancel.addEventListener("click", closeModal);
    row.append(cancel, ...buttons);
    return row;
  };

  switch (info.strategy) {
    case "apiKey": {
      nameField();
      const keyInput = document.createElement("input");
      keyInput.placeholder = "Paste your API key";
      keyInput.type = "password";
      keyInput.autocomplete = "off";
      form.append(field("API key", keyInput));
      const button = el("button", "btn primary", "Connect") as HTMLButtonElement;
      button.addEventListener("click", () => {
        if (!keyInput.value.trim()) return;
        start({ method: "apiKey", apiKey: keyInput.value.trim() });
      });
      form.append(buttonRow(button));
      keyInput.focus();
      break;
    }
    case "browserOAuth":
    case "deviceOAuth": {
      if (info.provider !== "github-copilot") {
        nameField();
      }
      const button = el(
        "button",
        "btn primary",
        "Sign in…",
      ) as HTMLButtonElement;
      button.addEventListener("click", () => start({}));
      form.append(buttonRow(button));
      break;
    }
    case "isolatedCLIProfile": {
      form.append(
        el(
          "p",
          "hint",
          "Requires the grok CLI on PATH. The app runs `grok login --device-auth` with an isolated profile and reads the resulting auth.json.",
        ),
      );
      nameField();
      const button = el(
        "button",
        "btn primary",
        "Sign in…",
      ) as HTMLButtonElement;
      button.addEventListener("click", () => start({}));
      form.append(buttonRow(button));
      break;
    }
    case "isolatedWebSession": {
      nameField();
      const button = el(
        "button",
        "btn primary",
        "Sign in with browser…",
      ) as HTMLButtonElement;
      button.addEventListener("click", () => start({}));
      form.append(buttonRow(button));
      if (info.provider === "claude") {
        form.append(el("div", "divider-text", "or"));
        const tokenInput = document.createElement("input");
        tokenInput.placeholder = "sk-ant-oat01-…";
        tokenInput.type = "password";
        tokenInput.autocomplete = "off";
        form.append(field("Setup token (from `claude setup-token`)", tokenInput));
        const tokenButton = el(
          "button",
          "btn primary",
          "Connect with token",
        ) as HTMLButtonElement;
        tokenButton.addEventListener("click", () => {
          if (!tokenInput.value.trim()) return;
          start({ method: "claudeToken", token: tokenInput.value.trim() });
        });
        form.append(buttonRow(tokenButton));
      }
      break;
    }
  }
}

function field(text: string, input: HTMLElement): HTMLElement {
  const wrapper = el("label", "field");
  wrapper.append(el("span", undefined, text), input);
  return wrapper;
}

// ---------------------------------------------------------------------------
// Connect progress
// ---------------------------------------------------------------------------

function beginFlow(request: ConnectRequest): void {
  const form = document.getElementById("connect-form")!;
  const progress = document.getElementById("connect-progress")!;
  form.hidden = true;
  progress.hidden = false;
  progress.textContent = "";
  progress.append(el("div", "status-line", "Starting…"));
  const row = el("div", "button-row");
  const cancel = el("button", "btn ghost", "Cancel") as HTMLButtonElement;
  cancel.addEventListener("click", () => {
    if (activeFlowID) void api.connectCancel(activeFlowID);
    activeFlowID = null;
    closeModal();
  });
  row.append(cancel);
  progress.append(row);

  void api.connectStart(request).then((flowID) => {
    activeFlowID = flowID;
  });
}

function renderConnectEvent(event: ConnectEvent): void {
  const progress = document.getElementById("connect-progress")!;
  const form = document.getElementById("connect-form")!;
  progress.hidden = false;
  form.hidden = true;

  switch (event.type) {
    case "status": {
      progress.textContent = "";
      progress.append(el("div", "status-line", event.message));
      appendCancelRow(progress);
      break;
    }
    case "prompt": {
      progress.textContent = "";
      progress.append(
        el("div", "status-line", "Approve the sign-in in your browser:"),
      );
      const codeBox = el("div", "code-box");
      codeBox.append(el("span", "user-code", event.userCode));
      const copy = el("button", "btn ghost", "Copy code") as HTMLButtonElement;
      copy.addEventListener("click", () => {
        void navigator.clipboard.writeText(event.userCode);
        copy.textContent = "Copied";
      });
      codeBox.append(copy);
      progress.append(codeBox);
      progress.append(el("div", "hint", event.verificationURL));
      appendCancelRow(progress);
      break;
    }
    case "claude-organizations": {
      progress.textContent = "";
      progress.append(
        el("div", "status-line", "Choose which Claude organizations to add:"),
      );
      const list = el("div", "org-list");
      const boxes: HTMLInputElement[] = [];
      for (const org of event.organizations) {
        const checkbox = document.createElement("input");
        checkbox.type = "checkbox";
        checkbox.checked = true;
        checkbox.value = org.uuid;
        boxes.push(checkbox);
        const item = document.createElement("label");
        item.append(checkbox, el("span", undefined, org.name));
        list.append(item);
      }
      progress.append(list);
      const row = el("div", "button-row");
      const save = el(
        "button",
        "btn primary",
        "Add selected",
      ) as HTMLButtonElement;
      save.addEventListener("click", () => {
        const ids = boxes.filter((box) => box.checked).map((box) => box.value);
        if (activeFlowID) void api.claudeSelectOrgs(activeFlowID, ids);
        progress.append(el("div", "status-line", "Saving…"));
      });
      row.append(save);
      progress.append(row);
      break;
    }
    case "complete": {
      progress.textContent = "";
      progress.append(el("div", "status-line", "Connected."));
      activeFlowID = null;
      setTimeout(closeModal, 1200);
      break;
    }
    case "failed": {
      progress.textContent = "";
      progress.append(el("div", "error-text", event.message));
      const row = el("div", "button-row");
      const dismiss = el("button", "btn ghost", "Dismiss") as HTMLButtonElement;
      dismiss.addEventListener("click", closeModal);
      row.append(dismiss);
      progress.append(row);
      activeFlowID = null;
      break;
    }
  }
}

function appendCancelRow(progress: HTMLElement): void {
  const row = el("div", "button-row");
  const cancel = el("button", "btn ghost", "Cancel") as HTMLButtonElement;
  cancel.addEventListener("click", () => {
    if (activeFlowID) void api.connectCancel(activeFlowID);
    activeFlowID = null;
    closeModal();
  });
  row.append(cancel);
  progress.append(row);
}

// ---------------------------------------------------------------------------

function render(state: SettingsState): void {
  renderAccounts(state);
  renderProviders(state);
}

api.onState((payload) => render(payload.settings));
api.onConnectEvent(({ flowID, event }) => {
  if (activeFlowID && flowID !== activeFlowID) return;
  renderConnectEvent(event);
});
void api.getState().then((payload) => {
  render(payload.settings);
  // Dev/screenshot hook: ?demo-connect=<provider> opens the connect modal.
  const demo = new URLSearchParams(location.search).get("demo-connect");
  if (demo) {
    const info = payload.settings.providers.find((p) => p.provider === demo);
    if (info) selectProvider(info);
  }
});
