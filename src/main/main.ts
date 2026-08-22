// Entry point: app lifecycle, flags, tray/panel/widget construction.

import { app, session } from "electron";
import { join } from "node:path";
import { fileURLToPath } from "node:url";

import { AppModel, samplePersistedState } from "./appModel.js";
import {
  AppStateStore,
  SafeStorageCredentialStore,
  defaultCredentialFilePath,
  defaultStateFilePath,
} from "./storage.js";
import { WindowManager } from "./windows.js";
import { TrayController } from "./tray.js";
import { registerIPC } from "./ipc.js";
import { DEVELOPMENT_REFRESH_POLICY, RELEASE_REFRESH_POLICY } from "../core/refresh/refresh.js";
import type { SessionCookie } from "../core/providers/claude.js";

const here = fileURLToPath(new URL(".", import.meta.url));
const rendererRoot = join(here, "..", "renderer");
const preloadPath = (name: string) => join(here, "..", "preload", `${name}.cjs`);

const args = process.argv.slice(2);
const isSampleData = args.includes("--sample-data");
const isSmoke = args.includes("--smoke");
const smokeShot = args.find((arg) => arg.startsWith("--smoke-shot="))?.split("=")[1];
const smokeSettingsShot = args
  .find((arg) => arg.startsWith("--smoke-settings-shot="))
  ?.split("=")[1];
const isDev = args.includes("--dev") || process.env["AUM_DEV"] === "1";

// The tray app is single-instance.
const gotLock = app.requestSingleInstanceLock();
if (!gotLock) {
  app.quit();
} else {
  void bootstrap();
}

async function bootstrap(): Promise<void> {
  await app.whenReady();

  // Tray apps do not show a dock icon on macOS.
  if (process.platform === "darwin") app.dock?.hide();

  const stateStore = new AppStateStore(defaultStateFilePath());
  if (isSampleData) {
    await stateStore.save(samplePersistedState(args.includes("--show-widget")));
  }

  const credentialStore = new SafeStorageCredentialStore(defaultCredentialFilePath());

  const cookieSource = async (partition: string): Promise<SessionCookie[] | null> => {
    try {
      const ses = session.fromPartition(partition);
      const cookies = await ses.cookies.get({});
      return cookies.map((cookie) => ({
        name: cookie.name,
        value: cookie.value,
        domain: cookie.domain ?? "",
        ...(cookie.expirationDate !== undefined
          ? { expirationDate: cookie.expirationDate }
          : {}),
      }));
    } catch {
      return null;
    }
  };

  const model = new AppModel({
    stateStore,
    credentialStore,
    cookieSource,
    refreshPolicy: isDev ? DEVELOPMENT_REFRESH_POLICY : RELEASE_REFRESH_POLICY,
    isSampleData,
  });

  const windows = new WindowManager(model, rendererRoot, preloadPath);

  let quitting = false;
  const onQuit = () => {
    quitting = true;
    model.stopAutomaticRefresh();
    app.quit();
  };

  const tray = new TrayController(model, windows, onQuit);
  registerIPC({ model, windows, tray, onQuit });

  await model.start();
  tray.install();
  windows.syncWidget();
  if (!isSampleData) model.startAutomaticRefresh();

  app.on("second-instance", () => {
    windows.togglePanel();
  });
  app.on("window-all-closed", () => {
    // Tray app: keep running with no windows.
  });
  app.on("before-quit", () => {
    quitting = true;
    tray.destroy();
  });
  void quitting;

  if (isSmoke) {
    // Smoke mode: open the panel or settings, optionally capture a screenshot, exit 0.
    setTimeout(async () => {
      try {
        if (smokeSettingsShot) {
          const demoConnect = args
            .find((arg) => arg.startsWith("--smoke-connect="))
            ?.split("=")[1];
          const settings = windows.openSettings(
            demoConnect ? `?demo-connect=${demoConnect}` : undefined,
          );
          await new Promise((resolve) => setTimeout(resolve, 1800));
          const image = await settings.webContents.capturePage();
          const { writeFileSync } = await import("node:fs");
          writeFileSync(smokeSettingsShot, image.toPNG());
          console.log(`smoke-settings-shot written to ${smokeSettingsShot}`);
        } else {
          windows.togglePanel();
          await new Promise((resolve) => setTimeout(resolve, 1500));
          if (smokeShot) {
            const panel = windows.panelWindow();
            const image = await panel.webContents.capturePage();
            const { writeFileSync } = await import("node:fs");
            writeFileSync(smokeShot, image.toPNG());
            console.log(`smoke-shot written to ${smokeShot}`);
          }
        }
        console.log("SMOKE OK");
        process.exitCode = 0;
      } catch (error) {
        console.error("SMOKE FAILED", error);
        process.exitCode = 1;
      } finally {
        app.quit();
      }
    }, 1000);
  }
}
