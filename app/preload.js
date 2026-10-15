"use strict";
const { contextBridge, ipcRenderer } = require("electron");

contextBridge.exposeInMainWorld("rc", {
  loadData: () => ipcRenderer.invoke("data:load"),
  wowState: () => ipcRenderer.invoke("wow:state"),
  chooseWow: () => ipcRenderer.invoke("wow:choose"),
  setFlavors: (list) => ipcRenderer.invoke("wow:setFlavors", list),
  savedList: () => ipcRenderer.invoke("saved:list"),
  savePut: (entry) => ipcRenderer.invoke("saved:put", entry),
  saveRemove: (key) => ipcRenderer.invoke("saved:remove", key),
});
