// IPC wiring between renderers and the main-process model/flows.

import { ipcMain, type WebContents } from "electron";
import { randomUUID } from "node:crypto";
import type { AppModel } from "./appModel.js";
import type { WindowManager } from "./windows.js";
import type { TrayController } from "./tray.js";
import {
  cancelClaudeSelection,
  resolveClaudeSelection,
  runConnectFlow,
  type ConnectContext,
} from "./connect.js";
import {
  IPC,
  type ClaudeOrgSelection,
  type ConnectEvent,
  type ConnectRequest,
  type ProviderInfo,
  type RendererState,
  type SettingsState,
} from "../shared/ipc.js";
import {
  connectableProviders,
  providerCatalog,
} from "../core/catalog.js";
import { timelinePresentation } from "../core/presentation/timeline.js";
import { isProvider, type UsageSectionID } from "../core/models.js";

function providerInfos(): ProviderInfo[] {
  return providerCatalog.map((definition) => ({
    provider: definition.provider,
    displayName: definition.displayName,
    connectionDetail: definition.connectionDetail,
    color: definition.color,
    releaseState: definition.releaseState,
    strategy: definition.connectionStrategy.type,
    dashboardURL: definition.dashboardURL,
  }));
}

function rendererState(model: AppModel): RendererState {
  const accounts = model.accounts;
  return {
    isSampleData: model.isSampleData,
    platform: process.platform,
    accounts,
    timeline: timelinePresentation(accounts, new Date()),
    collapsedSections: model.collapsedSections,
    isFloatingWidgetVisible: model.isFloatingWidgetVisible,
    anyRefreshing: model.anyRefreshing,
    providers: providerInfos(),
  };
}

function settingsState(model: AppModel): SettingsState {
  const definitions = new Map(providerCatalog.map((entry) => [entry.provider, entry]));
  return {
    isSampleData: model.isSampleData,
    providers: providerInfos().filter((p) =>
      connectableProviders().some((d) => d.provider === p.provider),
    ),
    accounts: model.accounts.map((state) => {
      const definition = definitions.get(state.account.provider)!;
      return {
        account: state.account,
        providerInfo: {
          provider: definition.provider,
          displayName: definition.displayName,
          connectionDetail: definition.connectionDetail,
          color: definition.color,
          releaseState: definition.releaseState,
          strategy: definition.connectionStrategy.type,
          dashboardURL: definition.dashboardURL,
        },
        error: state.error,
        isRefreshing: state.isRefreshing,
        lastFetchedAt: state.snapshot?.fetchedAt ?? null,
      };
    }),
  };
}

export function registerIPC(input: {
  model: AppModel;
  windows: WindowManager;
  tray: TrayController;
  onQuit: () => void;
}): void {
  const { model, windows, tray, onQuit } = input;
  const flows = new Map<string, { cancelled: boolean; sender: WebContents }>();

  const pushState = () => {
    windows.broadcast(IPC.stateUpdated, {
      panel: rendererState(model),
      settings: settingsState(model),
    });
    tray.update();
  };
  model.on("changed", pushState);

  ipcMain.handle(IPC.stateGet, () => ({
    panel: rendererState(model),
    settings: settingsState(model),
  }));

  ipcMain.handle(IPC.refreshAll, () => model.refreshAllAccounts());
  ipcMain.handle(IPC.refreshAccount, (_event, accountID: string) =>
    model.refreshAccount(accountID),
  );
  ipcMain.handle(IPC.toggleSection, (_event, section: UsageSectionID) =>
    model.toggleSection(section),
  );
  ipcMain.handle(IPC.openSettings, () => windows.openSettings());
  ipcMain.handle(IPC.openDashboard, (_event, accountID: string) =>
    windows.openDashboard(accountID),
  );
  ipcMain.handle(IPC.toggleWidget, async () => {
    await model.setFloatingWidgetVisible(!model.isFloatingWidgetVisible);
    windows.syncWidget();
  });
  ipcMain.handle(IPC.quit, () => onQuit());
  ipcMain.handle("panel:content-height", (_event, height: number) => {
    if (typeof height === "number" && Number.isFinite(height)) {
      windows.setPanelContentHeight(height);
    }
  });

  ipcMain.handle(IPC.settingsGetState, () => settingsState(model));

  ipcMain.handle(IPC.removeAccount, async (_event, accountID: string) => {
    const account = model.account(accountID);
    await model.removeAccount(accountID);
    // Clear the session partition only when no remaining account uses it.
    if (account?.sessionPartition) {
      const stillUsed = model.accounts.some(
        (state) => state.account.sessionPartition === account.sessionPartition,
      );
      if (!stillUsed) {
        await windows.clearPartitionData(account.sessionPartition);
      }
    }
  });

  ipcMain.handle(IPC.connectStart, (event, request: ConnectRequest) => {
    if (!isProvider(request.provider)) {
      throw new Error(`Unknown provider: ${request.provider}`);
    }
    const flowID = randomUUID();
    const sender = event.sender;
    const flow = { cancelled: false, sender };
    flows.set(flowID, flow);

    const ctx: ConnectContext = {
      appModel: model,
      flowID,
      openLoginWindow: windows.openLoginWindow,
      clearPartitionData: (partition) => windows.clearPartitionData(partition),
      emit: (connectEvent: ConnectEvent) => {
        if (!sender.isDestroyed()) {
          sender.send(IPC.connectEvent, { flowID, event: connectEvent });
        }
      },
      isCancelled: () => flow.cancelled || sender.isDestroyed(),
    };

    void runConnectFlow(ctx, request).finally(() => {
      flows.delete(flowID);
    });
    return flowID;
  });

  ipcMain.handle(IPC.connectClaudeOrgs, (_event, flowID: string, selection: ClaudeOrgSelection) => {
    return resolveClaudeSelection(flowID, selection.organizationIDs);
  });

  ipcMain.handle(IPC.connectCancel, (_event, flowID: string) => {
    const flow = flows.get(flowID);
    if (flow) flow.cancelled = true;
    cancelClaudeSelection(flowID);
  });
}
