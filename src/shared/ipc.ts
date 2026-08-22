// IPC contract shared between main and renderers.

import type {
  Provider,
  SubscriptionAccount,
  UsageSectionID,
} from "../core/models.js";
import type { AccountViewState, TimelinePresentation } from "../core/presentation/timeline.js";

export interface RendererState {
  isSampleData: boolean;
  platform: string;
  accounts: AccountViewState[];
  timeline: TimelinePresentation;
  collapsedSections: UsageSectionID[];
  isFloatingWidgetVisible: boolean;
  anyRefreshing: boolean;
  providers: ProviderInfo[];
}

export interface ProviderInfo {
  provider: Provider;
  displayName: string;
  connectionDetail: string;
  color: string;
  releaseState: "qualified" | "experimental" | "unavailable";
  strategy: "isolatedWebSession" | "browserOAuth" | "deviceOAuth" | "apiKey" | "isolatedCLIProfile";
  dashboardURL: string | null;
}

export interface SettingsAccount {
  account: SubscriptionAccount;
  providerInfo: ProviderInfo;
  error: "requiresReauthentication" | "temporarilyUnavailable" | null;
  isRefreshing: boolean;
  lastFetchedAt: string | null;
}

export interface SettingsState {
  accounts: SettingsAccount[];
  providers: ProviderInfo[];
  isSampleData: boolean;
}

// Connection flows

export type ConnectMethod = "auto" | "apiKey" | "claudeToken";

export interface ConnectRequest {
  provider: Provider;
  method: ConnectMethod;
  displayName?: string;
  apiKey?: string;
  token?: string;
  // Reconnect an existing account instead of creating a new one.
  reconnectAccountID?: string;
}

export type ConnectEvent =
  | { type: "prompt"; verificationURL: string; userCode: string; expiresAt?: string }
  | { type: "status"; message: string }
  | {
      type: "claude-organizations";
      organizations: { uuid: string; name: string; capabilities: string[] }[];
    }
  | { type: "complete"; accountIDs: string[] }
  | { type: "failed"; message: string };

export interface ClaudeOrgSelection {
  organizationIDs: string[];
}

export const IPC = {
  stateGet: "state:get",
  stateUpdated: "state:updated",
  refreshAll: "panel:refresh-all",
  refreshAccount: "panel:refresh-account",
  toggleSection: "panel:toggle-section",
  openSettings: "panel:open-settings",
  openDashboard: "panel:open-dashboard",
  toggleWidget: "panel:toggle-widget",
  quit: "panel:quit",
  settingsGetState: "settings:get-state",
  connectStart: "connect:start",
  connectEvent: "connect:event",
  connectClaudeOrgs: "connect:claude-select-orgs",
  connectCancel: "connect:cancel",
  removeAccount: "settings:remove-account",
  widgetMoved: "widget:moved",
} as const;
