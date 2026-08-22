// System tray: dynamic gauge icon + tooltip summary + click behavior.

import { Menu, Tray, nativeImage, type NativeImage } from "electron";
import type { AppModel } from "./appModel.js";
import type { WindowManager } from "./windows.js";
import { tightestWindow, traySummaryText } from "../core/presentation/timeline.js";
import { gaugeIconPNG } from "./png.js";
import { providerDefinition } from "../core/catalog.js";

export class TrayController {
  private tray: Tray | null = null;
  private readonly icons = new Map<string, NativeImage>();

  constructor(
    private readonly model: AppModel,
    private readonly windows: WindowManager,
    private readonly onQuit: () => void,
  ) {}

  install(): void {
    const tray = new Tray(this.iconFor(null));
    this.tray = tray;
    tray.setToolTip("Agentic Usage Meter");
    tray.on("click", () => {
      this.windows.togglePanel(tray.getBounds());
    });
    tray.on("right-click", () => {
      tray.popUpContextMenu(
        Menu.buildFromTemplate([
          { label: "Show Usage", click: () => this.windows.togglePanel(tray.getBounds()) },
          { label: "Refresh", click: () => void this.model.refreshAllAccounts() },
          { type: "separator" },
          { label: "Settings…", click: () => this.windows.openSettings() },
          { type: "separator" },
          { label: "Quit Agentic Usage Meter", click: () => this.onQuit() },
        ]),
      );
    });
    this.update();
  }

  update(): void {
    if (!this.tray) return;
    const snapshots = this.model.snapshots;
    const tightest = tightestWindow(snapshots);
    const fraction =
      tightest === null ? null : 1 - tightest.window.consumedFraction;
    this.tray.setImage(this.iconFor(fraction));
    this.tray.setToolTip(this.tooltip());
  }

  private iconFor(fraction: number | null): NativeImage {
    const key = fraction === null ? "none" : String(Math.round(fraction * 20) / 20);
    let icon = this.icons.get(key);
    if (!icon) {
      const png32 = gaugeIconPNG(fraction, 32);
      const png16 = gaugeIconPNG(fraction, 16);
      icon = nativeImage.createEmpty();
      icon.addRepresentation({ scaleFactor: 1, buffer: png16 });
      icon.addRepresentation({ scaleFactor: 2, buffer: png32 });
      this.icons.set(key, icon);
    }
    return icon;
  }

  private tooltip(): string {
    const lines = ["Agentic Usage Meter"];
    const summary = traySummaryText(this.model.snapshots);
    if (summary) lines.push(`Tightest window: ${summary} remaining`);
    for (const state of this.model.accounts) {
      const snapshot = state.snapshot;
      const provider = providerDefinition(state.account.provider).displayName;
      if (!snapshot || snapshot.windows.length === 0) {
        if (state.error === "requiresReauthentication") {
          lines.push(`${provider} ${state.account.displayName}: sign-in required`);
        }
        continue;
      }
      const tightestForAccount = tightestWindow([snapshot]);
      if (tightestForAccount) {
        const remaining = Math.round(
          (1 - tightestForAccount.window.consumedFraction) * 100,
        );
        lines.push(`${provider} ${state.account.displayName}: ${remaining}% remaining`);
      }
    }
    return lines.join("\n");
  }

  destroy(): void {
    this.tray?.destroy();
    this.tray = null;
  }
}
