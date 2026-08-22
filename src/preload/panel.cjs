// Preload for the tray panel (sandboxed → CommonJS, no Node APIs beyond
// ipcRenderer/contextBridge).
const { contextBridge, ipcRenderer } = require("electron");

contextBridge.exposeInMainWorld("usageMeter", {
  getState: () => ipcRenderer.invoke("state:get"),
  onState: (callback) => {
    const listener = (_event, payload) => callback(payload);
    ipcRenderer.on("state:updated", listener);
    return () => ipcRenderer.removeListener("state:updated", listener);
  },
  refreshAll: () => ipcRenderer.invoke("panel:refresh-all"),
  refreshAccount: (accountID) => ipcRenderer.invoke("panel:refresh-account", accountID),
  toggleSection: (section) => ipcRenderer.invoke("panel:toggle-section", section),
  openSettings: () => ipcRenderer.invoke("panel:open-settings"),
  openDashboard: (accountID) => ipcRenderer.invoke("panel:open-dashboard", accountID),
  toggleWidget: () => ipcRenderer.invoke("panel:toggle-widget"),
  quit: () => ipcRenderer.invoke("panel:quit"),
  setContentHeight: (height) => ipcRenderer.invoke("panel:content-height", height),
});
