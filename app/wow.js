// WoW folder handling for RCRotations Workshop: find the game versions in a
// WoW install and write the companion addon RCRotations_MyRotations, which
// RCRotations reads at login (see Sim.Workshop in SimImport.lua).
"use strict";
const fs = require("fs");
const path = require("path");

const ADDON = "RCRotations_MyRotations";
const FLAVOR_RE = /^_[a-z0-9_]+_$/;
const LABELS = {
  _classic_: "MoP Classic",
  _classic_era_: "Classic Era",
  _anniversary_: "Anniversary",
  _classic_ptr_: "Classic PTR",
  _retail_: "Retail",
  _ptr_: "Retail PTR",
  _beta_: "Beta",
};
const DEFAULT_INTERFACE = "11508, 11509, 20505, 20506, 30405, 40402, 50504, 16001";

function isDir(p) {
  try { return fs.statSync(p).isDirectory(); } catch (e) { return false; }
}

// Accept the WoW folder itself, a version folder (_classic_) or an AddOns
// folder, and return the WoW folder.
function normalizeRoot(p) {
  if (!p) return null;
  let cur = path.resolve(p);
  for (let i = 0; i < 4; i++) {
    if (listFlavorDirs(cur).length) return cur;
    const parent = path.dirname(cur);
    if (parent === cur) break;
    cur = parent;
  }
  return null;
}

function listFlavorDirs(root) {
  let names = [];
  try { names = fs.readdirSync(root); } catch (e) { return []; }
  return names.filter((n) => FLAVOR_RE.test(n)
    && (isDir(path.join(root, n, "Interface", "AddOns")) || isDir(path.join(root, n, "WTF"))));
}

function detectFlavors(root) {
  return listFlavorDirs(root).map((dir) => ({
    dir,
    label: LABELS[dir] || dir.replace(/_/g, " ").trim(),
    hasAddon: isDir(path.join(root, dir, "Interface", "AddOns", "RCRotations")),
  }));
}

// Lua long string that can't be closed by the content.
function luaLong(s) {
  let n = 0;
  while (s.includes("]" + "=".repeat(n) + "]")) n++;
  const eq = "=".repeat(n);
  return "[" + eq + "[" + s + "]" + eq + "]";
}

function luaString(s) {
  return '"' + String(s)
    .replace(/[\x00-\x08\x0b-\x1f\x7f]/g, "")
    .replace(/\\/g, "\\\\").replace(/"/g, '\\"').replace(/\n/g, "\\n").replace(/\r/g, "") + '"';
}

const TOKENS = new Set(["DEATHKNIGHT", "DRUID", "HUNTER", "MAGE", "MONK", "PALADIN", "PRIEST", "ROGUE", "SHAMAN", "WARLOCK", "WARRIOR"]);

function validEntry(e) {
  return e && TOKENS.has(e.token) && Number.isInteger(e.specIndex) && e.specIndex >= 0 && e.specIndex <= 4
    && typeof e.name === "string" && e.name.trim() && e.rotation && Array.isArray(e.rotation.priorityList);
}

function buildLua(entries) {
  const lines = [
    "-- Written by RCRotations Workshop. Change these rotations in the app; edits here are overwritten.",
    "RCRotations_MyRotations = {",
  ];
  for (const e of entries.filter(validEntry)) {
    const json = JSON.stringify(Object.assign({ type: "TypeAPL" }, e.rotation));
    lines.push("\t{ class = " + luaString(e.token) + ", spec = " + e.specIndex + ", name = " + luaString(e.name.trim().slice(0, 40)) + ", json = " + luaLong(json) + " },");
  }
  lines.push("}");
  return lines.join("\n") + "\n";
}

function interfaceFor(root, flavor) {
  try {
    const toc = fs.readFileSync(path.join(root, flavor, "Interface", "AddOns", "RCRotations", "RCRotations.toc"), "utf8");
    const m = toc.match(/^## Interface:\s*(.+)$/m);
    if (m) return m[1].trim();
  } catch (e) { /* fall through */ }
  return DEFAULT_INTERFACE;
}

function buildToc(iface) {
  return [
    "## Interface: " + iface,
    "## Title: RCRotations - My Rotations",
    "## Notes: Rotations saved from the RCRotations Workshop app.",
    "## Author: RCRotations Workshop",
    "## Dependencies: RCRotations",
    "",
    "MyRotations.lua",
    "",
  ].join("\n");
}

// Write the companion addon into each chosen version folder. Returns
// [{ flavor, ok, path | error }].
function writeCompanion(root, flavors, entries) {
  const results = [];
  for (const flavor of flavors) {
    if (!FLAVOR_RE.test(flavor)) {
      results.push({ flavor, ok: false, error: "Not a WoW version folder" });
      continue;
    }
    const addons = path.join(root, flavor, "Interface", "AddOns");
    const dir = path.join(addons, ADDON);
    try {
      if (!isDir(addons)) throw new Error("No Interface\\AddOns folder in " + flavor);
      fs.mkdirSync(dir, { recursive: true });
      fs.writeFileSync(path.join(dir, ADDON + ".toc"), buildToc(interfaceFor(root, flavor)), "utf8");
      fs.writeFileSync(path.join(dir, "MyRotations.lua"), buildLua(entries), "utf8");
      results.push({ flavor, ok: true, path: dir });
    } catch (err) {
      results.push({ flavor, ok: false, error: err.message });
    }
  }
  return results;
}

module.exports = { ADDON, normalizeRoot, detectFlavors, buildLua, buildToc, luaLong, luaString, writeCompanion, validEntry };
