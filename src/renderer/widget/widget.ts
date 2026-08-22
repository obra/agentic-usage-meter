// Floating widget renderer.

import { renderTimeline, type AccountStateLike } from "../timelineView.js";

interface WidgetAPI {
  getState(): Promise<{ panel: WidgetState }>;
  onState(callback: (payload: { panel: WidgetState }) => void): () => void;
  toggleWidget(): Promise<void>;
  openDashboard(accountID: string): Promise<void>;
  openSettings(): Promise<void>;
}

interface WidgetState {
  isSampleData: boolean;
  accounts: AccountStateLike[];
  timeline: Parameters<typeof renderTimeline>[1];
  collapsedSections: string[];
  providers: { provider: string; displayName: string; color: string }[];
}

const api = (window as unknown as { usageMeterWidget: WidgetAPI })
  .usageMeterWidget;

function render(state: WidgetState): void {
  (document.getElementById("sample") as HTMLElement).hidden = !state.isSampleData;
  const content = document.getElementById("content") as HTMLElement;
  renderTimeline(content, state.timeline, state.collapsedSections, state.accounts, {
    providerColor: (provider) =>
      state.providers.find((info) => info.provider === provider)?.color ??
      "#8e8e93",
    onToggleSection: () => {
      // Sections toggle from the panel; the widget mirrors that state.
    },
    onOpenAccount: (accountID) => void api.openDashboard(accountID),
  });
}

document.getElementById("close")!.addEventListener("click", () => {
  void api.toggleWidget();
});
document.getElementById("settings")!.addEventListener("click", () => {
  void api.openSettings();
});

api.onState((payload) => render(payload.panel));
void api.getState().then((payload) => render(payload.panel));
