// Preload for the settings window (sandboxed → CommonJS).
const { contextBridge, ipcRenderer } = require("electron");

contextBridge.exposeInMainWorld("usageMeterSettings", {
  getState: () => ipcRenderer.invoke("state:get"),
  onState: (callback) => {
    const listener = (_event, payload) => callback(payload);
    ipcRenderer.on("state:updated", listener);
    return () => ipcRenderer.removeListener("state:updated", listener);
  },
  connectStart: (request) => ipcRenderer.invoke("connect:start", request),
  onConnectEvent: (callback) => {
    const listener = (_event, payload) => callback(payload);
    ipcRenderer.on("connect:event", listener);
    return () => ipcRenderer.removeListener("connect:event", listener);
  },
  claudeSelectOrgs: (flowID, organizationIDs) =>
    ipcRenderer.invoke("connect:claude-select-orgs", flowID, { organizationIDs }),
  connectCancel: (flowID) => ipcRenderer.invoke("connect:cancel", flowID),
  removeAccount: (accountID) => ipcRenderer.invoke("settings:remove-account", accountID),
  refreshAccount: (accountID) => ipcRenderer.invoke("panel:refresh-account", accountID),
  openDashboard: (accountID) => ipcRenderer.invoke("panel:open-dashboard", accountID),
});
