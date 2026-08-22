// Window management: tray panel, settings, floating widget, provider login
// windows, and per-account embedded dashboards.

import { BrowserWindow, screen, session, shell, type Rectangle, type Session } from "electron";
import { join } from "node:path";
import type { AppModel } from "./appModel.js";
import { providerDefinition } from "../core/catalog.js";
import type { LoginWindowHandle, LoginWindowOpener } from "./connect.js";
import type { SessionCookie } from "../core/providers/claude.js";

const PANEL_WIDTH = 411;
const PANEL_MIN_HEIGHT = 140;
const PANEL_MAX_HEIGHT = 640;

export class WindowManager {
  private panel: BrowserWindow | null = null;
  private settings: BrowserWindow | null = null;
  private widget: BrowserWindow | null = null;

  constructor(
    private readonly model: AppModel,
    private readonly rendererRoot: string,
    private readonly preloadPath: (name: string) => string,
  ) {}

  // ------------------------------------------------------------------ panel

  panelWindow(): BrowserWindow {
    if (this.panel && !this.panel.isDestroyed()) return this.panel;
    const window = new BrowserWindow({
      width: PANEL_WIDTH,
      height: PANEL_MIN_HEIGHT,
      minWidth: PANEL_WIDTH,
      maxWidth: PANEL_WIDTH,
      minHeight: PANEL_MIN_HEIGHT,
      maxHeight: PANEL_MAX_HEIGHT,
      show: false,
      frame: false,
      resizable: false,
      skipTaskbar: true,
      alwaysOnTop: true,
      fullscreenable: false,
      webPreferences: {
        preload: this.preloadPath("panel"),
        contextIsolation: true,
        nodeIntegration: false,
      },
    });
    window.setMenu(null);
    window.on("blur", () => {
      if (!window.webContents.isDevToolsOpened()) this.hidePanel();
    });
    window.on("closed", () => {
      this.panel = null;
    });
    void window.loadFile(join(this.rendererRoot, "panel", "index.html"));
    this.panel = window;
    return window;
  }

  togglePanel(trayBounds?: Rectangle): void {
    const window = this.panelWindow();
    if (window.isVisible()) {
      this.hidePanel();
      return;
    }
    if (trayBounds) {
      this.positionPanel(window, trayBounds);
    } else {
      window.center();
    }
    window.show();
    window.focus();
  }

  hidePanel(): void {
    if (this.panel && !this.panel.isDestroyed()) this.panel.hide();
  }

  private positionPanel(window: BrowserWindow, trayBounds: Rectangle): void {
    const size = window.getSize();
    const width = size[0] ?? PANEL_WIDTH;
    const height = size[1] ?? PANEL_MIN_HEIGHT;
    const display = screen.getDisplayNearestPoint({
      x: trayBounds.x,
      y: trayBounds.y,
    });
    const workArea = display.workArea;

    let x = Math.round(trayBounds.x + trayBounds.width / 2 - width / 2);
    let y: number;
    if (process.platform === "darwin") {
      // Menu bar at top: panel hangs below the tray icon.
      y = Math.round(trayBounds.y + trayBounds.height + 4);
    } else {
      // Windows/Linux: taskbar tray, panel opens above the icon.
      y = Math.round(trayBounds.y - height - 8);
      if (y < workArea.y) y = Math.round(trayBounds.y + trayBounds.height + 8);
    }
    x = Math.min(Math.max(x, workArea.x), workArea.x + workArea.width - width);
    y = Math.min(Math.max(y, workArea.y), workArea.y + workArea.height - height);
    window.setPosition(x, y, false);
  }

  // Renderer reports its content height; clamp and resize.
  setPanelContentHeight(height: number): void {
    const window = this.panel;
    if (!window || window.isDestroyed()) return;
    const clamped = Math.round(
      Math.min(Math.max(height, PANEL_MIN_HEIGHT), PANEL_MAX_HEIGHT),
    );
    const size = window.getSize();
    const width = size[0] ?? PANEL_WIDTH;
    const current = size[1] ?? 0;
    if (current !== clamped) window.setSize(width, clamped, false);
  }

  // --------------------------------------------------------------- settings

  openSettings(search?: string): BrowserWindow {
    if (this.settings && !this.settings.isDestroyed()) {
      this.settings.show();
      this.settings.focus();
      return this.settings;
    }
    const window = new BrowserWindow({
      width: 780,
      height: 600,
      minWidth: 640,
      minHeight: 480,
      show: false,
      title: "Agentic Usage Meter Settings",
      webPreferences: {
        preload: this.preloadPath("settings"),
        contextIsolation: true,
        nodeIntegration: false,
      },
    });
    window.setMenu(null);
    window.once("ready-to-show", () => window.show());
    window.on("closed", () => {
      this.settings = null;
    });
    void window.loadFile(
      join(this.rendererRoot, "settings", "index.html"),
      search ? { search } : undefined,
    );
    this.settings = window;
    return window;
  }

  // ----------------------------------------------------------------- widget

  syncWidget(): void {
    if (this.model.isFloatingWidgetVisible) {
      this.showWidget();
    } else {
      this.hideWidget();
    }
  }

  private showWidget(): void {
    if (this.widget && !this.widget.isDestroyed()) {
      this.widget.show();
      return;
    }
    const placement = this.model.floatingWidgetPlacement();
    const options: ConstructorParameters<typeof BrowserWindow>[0] = {
      width: placement?.width ?? 411,
      height: placement?.height ?? 300,
      minWidth: 320,
      minHeight: 140,
      show: false,
      frame: false,
      resizable: true,
      skipTaskbar: true,
      alwaysOnTop: true,
      fullscreenable: false,
      title: "Agentic Usage",
      webPreferences: {
        preload: this.preloadPath("widget"),
        contextIsolation: true,
        nodeIntegration: false,
      },
    };
    if (placement) {
      options.x = placement.x;
      options.y = placement.y;
    }
    const window = new BrowserWindow(options);
    window.setMenu(null);
    const savePlacement = () => {
      if (window.isDestroyed()) return;
      const size = window.getSize();
      const position = window.getPosition();
      void this.model.setFloatingWidgetPlacement({
        x: position[0] ?? 0,
        y: position[1] ?? 0,
        width: size[0] ?? 411,
        height: size[1] ?? 300,
      });
    };
    window.on("moved", savePlacement);
    window.on("resized", savePlacement);
    window.on("close", () => {
      // Closing the widget means hiding it.
      void this.model.setFloatingWidgetVisible(false);
    });
    window.on("closed", () => {
      this.widget = null;
    });
    window.once("ready-to-show", () => window.show());
    void window.loadFile(join(this.rendererRoot, "widget", "index.html"));
    this.widget = window;
  }

  private hideWidget(): void {
    if (this.widget && !this.widget.isDestroyed()) {
      this.widget.destroy();
    }
    this.widget = null;
  }

  // ------------------------------------------------------------------ login

  openLoginWindow: LoginWindowOpener = async ({ partition, url, title }) => {
    const ses = session.fromPartition(partition);
    const window = new BrowserWindow({
      width: 560,
      height: 720,
      show: true,
      autoHideMenuBar: true,
      title,
      webPreferences: { session: ses },
    });
    window.setMenu(null);
    // Popups (OAuth interstitials) open in a child window on the same
    // partition, mirroring the macOS popup panel behavior.
    window.webContents.setWindowOpenHandler(({ url: popupURL }) => {
      return {
        action: "allow",
        overrideBrowserWindowOptions: {
          width: 560,
          height: 680,
          autoHideMenuBar: true,
          title,
          webPreferences: { session: ses },
        },
      };
    });
    await window.loadURL(url);

    const cookieListeners: (() => void)[] = [];
    const navigationListeners: ((url: string) => void)[] = [];
    ses.cookies.on("changed", () => {
      for (const listener of cookieListeners) listener();
    });
    window.webContents.on("did-navigate", (_event, navigatedURL) => {
      for (const listener of navigationListeners) listener(navigatedURL);
    });
    window.webContents.on("did-navigate-in-page", (_event, navigatedURL) => {
      for (const listener of navigationListeners) listener(navigatedURL);
    });

    const handle: LoginWindowHandle = {
      partition,
      close: () => {
        if (!window.isDestroyed()) window.destroy();
      },
      onCookiesChanged: (cb) => cookieListeners.push(cb),
      onNavigated: (cb) => navigationListeners.push(cb),
      cookies: async (filterURL: string) => {
        const cookies = filterURL
          ? await ses.cookies.get({ url: filterURL })
          : await ses.cookies.get({});
        return cookies.map(
          (cookie): SessionCookie => ({
            name: cookie.name,
            value: cookie.value,
            domain: cookie.domain ?? "",
            ...(cookie.expirationDate !== undefined
              ? { expirationDate: cookie.expirationDate }
              : {}),
          }),
        );
      },
    };
    return handle;
  };

  async clearPartitionData(partition: string): Promise<void> {
    const ses = session.fromPartition(partition);
    await ses.clearStorageData();
    await ses.clearCache();
  }

  // -------------------------------------------------------------- dashboard

  async openDashboard(accountID: string): Promise<void> {
    const account = this.model.account(accountID);
    if (!account) return;
    const url = providerDefinition(account.provider).dashboardURL;
    if (!url) return;
    if (account.sessionPartition) {
      // Open an embedded, logged-in dashboard on the account's session.
      const ses = session.fromPartition(account.sessionPartition);
      const window = new BrowserWindow({
        width: 960,
        height: 720,
        show: true,
        autoHideMenuBar: true,
        title: `${providerDefinition(account.provider).displayName} — ${account.displayName}`,
        webPreferences: { session: ses },
      });
      window.setMenu(null);
      window.webContents.setWindowOpenHandler(({ url: external }) => {
        void shell.openExternal(external);
        return { action: "deny" };
      });
      await window.loadURL(url);
      return;
    }
    await shell.openExternal(url);
  }

  // -------------------------------------------------------------- broadcast

  broadcast(channel: string, payload: unknown): void {
    for (const window of [this.panel, this.settings, this.widget]) {
      if (window && !window.isDestroyed()) {
        window.webContents.send(channel, payload);
      }
    }
  }

  hideAll(): void {
    this.hidePanel();
    if (this.settings && !this.settings.isDestroyed()) this.settings.close();
    this.settings = null;
    if (this.widget && !this.widget.isDestroyed()) this.widget.destroy();
    this.widget = null;
  }
}
