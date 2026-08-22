// Preload for the floating widget (sandboxed → CommonJS).
const { contextBridge, ipcRenderer } = require("electron");

contextBridge.exposeInMainWorld("usageMeterWidget", {
  getState: () => ipcRenderer.invoke("state:get"),
  onState: (callback) => {
    const listener = (_event, payload) => callback(payload);
    ipcRenderer.on("state:updated", listener);
    return () => ipcRenderer.removeListener("state:updated", listener);
  },
  toggleWidget: () => ipcRenderer.invoke("panel:toggle-widget"),
  openDashboard: (accountID) => ipcRenderer.invoke("panel:open-dashboard", accountID),
  openSettings: () => ipcRenderer.invoke("panel:open-settings"),
});
