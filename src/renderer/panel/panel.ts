// Tray panel renderer.

import { renderTimeline, type AccountStateLike } from "../timelineView.js";

interface PanelAPI {
  getState(): Promise<{ panel: PanelState }>;
  onState(callback: (payload: { panel: PanelState }) => void): () => void;
  refreshAll(): Promise<void>;
  refreshAccount(accountID: string): Promise<void>;
  toggleSection(section: string): Promise<void>;
  openSettings(): Promise<void>;
  openDashboard(accountID: string): Promise<void>;
  toggleWidget(): Promise<void>;
  quit(): Promise<void>;
  setContentHeight(height: number): Promise<void>;
}

interface PanelState {
  isSampleData: boolean;
  accounts: AccountStateLike[];
  timeline: Parameters<typeof renderTimeline>[1];
  collapsedSections: string[];
  isFloatingWidgetVisible: boolean;
  anyRefreshing: boolean;
  providers: { provider: string; displayName: string; color: string }[];
}

const api = (window as unknown as { usageMeter: PanelAPI }).usageMeter;

let latest: PanelState | null = null;

function providerColor(state: PanelState, provider: string): string {
  return (
    state.providers.find((info) => info.provider === provider)?.color ?? "#8e8e93"
  );
}

function render(state: PanelState): void {
  latest = state;
  (document.getElementById("sample") as HTMLElement).hidden = !state.isSampleData;
  const refreshButton = document.getElementById("refresh") as HTMLButtonElement;
  refreshButton.disabled = state.anyRefreshing;
  refreshButton.classList.toggle("spinning", state.anyRefreshing);
  (document.getElementById("widget-toggle") as HTMLButtonElement).textContent =
    state.isFloatingWidgetVisible ? "Hide Widget" : "Show Widget";

  const content = document.getElementById("content") as HTMLElement;
  renderTimeline(content, state.timeline, state.collapsedSections, state.accounts, {
    providerColor: (provider) => providerColor(state, provider),
    onToggleSection: (section) => void api.toggleSection(section),
    onOpenAccount: (accountID) => void api.openDashboard(accountID),
    onReconnect: () => void api.openSettings(),
  });

  // Report content height so the main process can fit the panel. The body is
  // pinned to 100vh with an internally scrolling .content area, so
  // body.scrollHeight always equals the current window height — measure the
  // content's natural height instead.
  requestAnimationFrame(() => {
    const header = document.querySelector<HTMLElement>(".header");
    const footer = document.querySelector<HTMLElement>(".footer");
    const content = document.getElementById("content");
    if (!header || !footer || !content) return;
    const height = header.offsetHeight + content.scrollHeight + footer.offsetHeight;
    void api.setContentHeight(height);
  });
}

document.getElementById("refresh")!.addEventListener("click", () => {
  void api.refreshAll();
});
document.getElementById("settings")!.addEventListener("click", () => {
  void api.openSettings();
});
document.getElementById("quit")!.addEventListener("click", () => {
  void api.quit();
});
document.getElementById("widget-toggle")!.addEventListener("click", () => {
  void api.toggleWidget();
});

api.onState((payload) => render(payload.panel));
void api.getState().then((payload) => render(payload.panel));

// Keep relative times fresh while the panel is open.
setInterval(() => {
  if (latest) render(latest);
}, 30_000);
