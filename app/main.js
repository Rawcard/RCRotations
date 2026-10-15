// RCRotations Workshop: Electron main process.
"use strict";
const { app, BrowserWindow, ipcMain, dialog, shell } = require("electron");
const fs = require("fs");
const path = require("path");
const https = require("https");
const wow = require("./wow");

const DATA_URL = "https://raw.githubusercontent.com/Rawcard/RCRotations/main/app/data/";
const userFile = (name) => path.join(app.getPath("userData"), name);

function readJSON(file, fallback) {
  try { return JSON.parse(fs.readFileSync(file, "utf8")); } catch (e) { return fallback; }
}
function writeJSON(file, value) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, JSON.stringify(value), "utf8");
}

function download(url, timeoutMs) {
  return new Promise((resolve, reject) => {
    const req = https.get(url, { headers: { "User-Agent": "RCRotations-Workshop" } }, (res) => {
      if (res.statusCode !== 200) { res.resume(); reject(new Error("HTTP " + res.statusCode)); return; }
      let body = "";
      res.setEncoding("utf8");
      res.on("data", (c) => (body += c));
      res.on("end", () => resolve(body));
    });
    req.setTimeout(timeoutMs, () => req.destroy(new Error("timed out")));
    req.on("error", reject);
  });
}

// Latest rotations from GitHub; falls back to the last download, then to the
// copy bundled with the app.
async function loadData() {
  const bundled = (name) => readJSON(path.join(__dirname, "data", name), null);
  try {
    const [rot, names] = await Promise.all([download(DATA_URL + "rotations.json", 10000), download(DATA_URL + "names.json", 10000)]);
    const r = JSON.parse(rot), n = JSON.parse(names);
    if (!Array.isArray(r.rotations) || !r.rotations.length) throw new Error("empty");
    writeJSON(userFile("cache-rotations.json"), r);
    writeJSON(userFile("cache-names.json"), n);
    writeJSON(userFile("cache-info.json"), { at: Date.now() });
    return { rotations: r.rotations, names: n, from: "github", at: Date.now() };
  } catch (err) {
    const r = readJSON(userFile("cache-rotations.json"), null);
    const n = readJSON(userFile("cache-names.json"), null);
    if (r && n) return { rotations: r.rotations, names: n, from: "cache", at: (readJSON(userFile("cache-info.json"), {}) || {}).at || 0, error: err.message };
    const br = bundled("rotations.json"), bn = bundled("names.json");
    return { rotations: br ? br.rotations : [], names: bn || { spells: {}, items: {} }, from: "bundled", at: 0, error: err.message };
  }
}

function settings() { return readJSON(userFile("settings.json"), {}); }
function saveSettings(s) { writeJSON(userFile("settings.json"), s); }
function saved() { return readJSON(userFile("my-rotations.json"), []); }

function wowState() {
  const s = settings();
  const root = s.wowRoot && wow.normalizeRoot(s.wowRoot);
  const flavors = root ? wow.detectFlavors(root) : [];
  const chosen = Array.isArray(s.flavors) ? s.flavors.filter((f) => flavors.some((x) => x.dir === f)) : flavors.filter((f) => f.hasAddon).map((f) => f.dir);
  return { root, flavors, chosen };
}

function writeAll() {
  const st = wowState();
  if (!st.root) return { ok: false, error: "Choose your World of Warcraft folder first." };
  if (!st.chosen.length) return { ok: false, error: "Pick at least one game version to save to." };
  const results = wow.writeCompanion(st.root, st.chosen, saved());
  const bad = results.filter((r) => !r.ok);
  return { ok: bad.length === 0, results, error: bad.length ? bad.map((b) => b.flavor + ": " + b.error).join("; ") : undefined };
}

function createWindow() {
  const win = new BrowserWindow({
    width: 1280, height: 860, minWidth: 420, minHeight: 500,
    title: "RCRotations Workshop",
    backgroundColor: "#121317",
    autoHideMenuBar: true,
    webPreferences: { preload: path.join(__dirname, "preload.js"), contextIsolation: true, sandbox: true, nodeIntegration: false },
  });
  win.webContents.setWindowOpenHandler(({ url }) => {
    if (/^https:\/\//.test(url)) shell.openExternal(url);
    return { action: "deny" };
  });
  win.webContents.on("will-navigate", (e) => e.preventDefault());
  win.loadFile(path.join(__dirname, "renderer", "index.html"));
}

ipcMain.handle("data:load", () => loadData());
ipcMain.handle("wow:state", () => wowState());
ipcMain.handle("wow:choose", async () => {
  const res = await dialog.showOpenDialog({ title: "Choose your World of Warcraft folder", properties: ["openDirectory"] });
  if (res.canceled || !res.filePaths[0]) return wowState();
  const root = wow.normalizeRoot(res.filePaths[0]);
  if (!root) return Object.assign(wowState(), { error: "That folder doesn't look like a World of Warcraft install. Pick the folder that has _classic_ (or _retail_) in it." });
  const s = settings();
  s.wowRoot = root;
  delete s.flavors;
  saveSettings(s);
  return wowState();
});
ipcMain.handle("wow:setFlavors", (_e, list) => {
  const s = settings();
  s.flavors = Array.isArray(list) ? list.filter((f) => typeof f === "string") : [];
  saveSettings(s);
  return wowState();
});
ipcMain.handle("saved:list", () => saved());
ipcMain.handle("saved:put", (_e, entry) => {
  if (!wow.validEntry(entry)) return { ok: false, error: "That rotation is missing its class, spec or lines." };
  const list = saved().filter((x) => !(x.token === entry.token && x.specIndex === entry.specIndex && x.name === entry.name));
  list.push({ token: entry.token, specIndex: entry.specIndex, name: entry.name.trim().slice(0, 40), rotation: entry.rotation, at: Date.now() });
  writeJSON(userFile("my-rotations.json"), list);
  return Object.assign(writeAll(), { saved: list });
});
ipcMain.handle("saved:remove", (_e, key) => {
  const list = saved().filter((x) => !(x.token === key.token && x.specIndex === key.specIndex && x.name === key.name));
  writeJSON(userFile("my-rotations.json"), list);
  return Object.assign(writeAll(), { saved: list });
});

app.whenReady().then(createWindow);
app.on("window-all-closed", () => app.quit());
