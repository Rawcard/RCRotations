// Electron smoke run: xvfb-run npx electron test/smoke-main.js
// Uses a fake WoW folder, opens the app, saves a rotation through the UI and
// checks that the companion addon file was written.
"use strict";
const { app, BrowserWindow } = require("electron");
const fs = require("fs");
const os = require("os");
const path = require("path");

const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "rcw-"));
const root = path.join(tmp, "World of Warcraft");
fs.mkdirSync(path.join(root, "_classic_", "Interface", "AddOns", "RCRotations"), { recursive: true });
app.setPath("userData", path.join(tmp, "userData"));
fs.mkdirSync(app.getPath("userData"), { recursive: true });
fs.writeFileSync(path.join(app.getPath("userData"), "settings.json"), JSON.stringify({ wowRoot: root }));

require("../main.js");

app.on("browser-window-created", (_e, win) => {
  win.webContents.on("did-finish-load", async () => {
    const wait = (ms) => new Promise((r) => setTimeout(r, ms));
    let out = { ok: false };
    try {
      for (let i = 0; i < 40; i++) {
        if (await win.webContents.executeJavaScript("document.querySelectorAll('.line').length > 0")) break;
        await wait(250);
      }
      out.lines = await win.webContents.executeJavaScript("document.querySelectorAll('.line').length");
      out.status = await win.webContents.executeJavaScript("document.getElementById('dataStatus').textContent");
      await win.webContents.executeJavaScript("document.getElementById('saveBtn').click(); document.getElementById('saveName').value = 'Smoke Test'; document.getElementById('saveGo').click();");
      await wait(1000);
      const file = path.join(root, "_classic_", "Interface", "AddOns", "RCRotations_MyRotations", "MyRotations.lua");
      out.written = fs.existsSync(file) && fs.readFileSync(file, "utf8").includes('name = "Smoke Test"');
      out.saved = await win.webContents.executeJavaScript("document.getElementById('savedList').textContent");
      out.ok = out.lines > 0 && out.written;
    } catch (err) { out.error = String(err); }
    console.log("SMOKE " + JSON.stringify(out));
    fs.rmSync(tmp, { recursive: true, force: true });
    app.exit(out.ok ? 0 : 1);
  });
});
