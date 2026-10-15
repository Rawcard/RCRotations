// node test/wow.test.js — checks the WoW folder logic against a fake install.
"use strict";
const fs = require("fs");
const os = require("os");
const path = require("path");
const assert = require("assert");
const wow = require("../wow");

let failed = 0;
function test(name, fn) {
  try { fn(); console.log("PASS " + name); } catch (e) { failed++; console.log("FAIL " + name + ": " + e.message); }
}

const root = fs.mkdtempSync(path.join(os.tmpdir(), "wow-"));
fs.mkdirSync(path.join(root, "_classic_", "Interface", "AddOns", "RCRotations"), { recursive: true });
fs.writeFileSync(path.join(root, "_classic_", "Interface", "AddOns", "RCRotations", "RCRotations.toc"), "## Interface: 50504, 50503\n## Title: RCRotations\n");
fs.mkdirSync(path.join(root, "_classic_era_", "Interface", "AddOns"), { recursive: true });
fs.mkdirSync(path.join(root, "Data"), { recursive: true });

const rot = { priorityList: [{ action: { castSpell: { spellId: { spellId: 49020 } } } }] };
const entry = { token: "DEATHKNIGHT", specIndex: 2, name: 'My "Frost" ]]', rotation: rot };

test("finds the WoW folder from itself, a version folder or AddOns", () => {
  assert.strictEqual(wow.normalizeRoot(root), root);
  assert.strictEqual(wow.normalizeRoot(path.join(root, "_classic_")), root);
  assert.strictEqual(wow.normalizeRoot(path.join(root, "_classic_", "Interface", "AddOns")), root);
  assert.strictEqual(wow.normalizeRoot(os.tmpdir() + path.sep + "nope-" + Date.now()), null);
});
test("lists game versions and whether RCRotations is installed", () => {
  const f = wow.detectFlavors(root);
  assert.deepStrictEqual(f.map((x) => [x.dir, x.hasAddon]).sort(), [["_classic_", true], ["_classic_era_", false]]);
  assert.strictEqual(f.find((x) => x.dir === "_classic_").label, "MoP Classic");
});
test("long strings can't be closed by their content", () => {
  assert.strictEqual(wow.luaLong("a]]b"), "[=[a]]b]=]");
  assert.strictEqual(wow.luaLong("x]=]y]]"), "[==[x]=]y]]]==]");
});
test("writes the companion addon with the installed TOC's interface", () => {
  const res = wow.writeCompanion(root, ["_classic_"], [entry]);
  assert.ok(res[0].ok, res[0].error);
  const dir = path.join(root, "_classic_", "Interface", "AddOns", wow.ADDON);
  const toc = fs.readFileSync(path.join(dir, wow.ADDON + ".toc"), "utf8");
  assert.ok(toc.includes("## Interface: 50504, 50503"));
  assert.ok(toc.includes("## Dependencies: RCRotations"));
  const lua = fs.readFileSync(path.join(dir, "MyRotations.lua"), "utf8");
  assert.ok(lua.includes('class = "DEATHKNIGHT", spec = 2'));
  assert.ok(lua.includes('name = "My \\"Frost\\" ]]"'));
});
test("refuses folders that aren't game versions", () => {
  const res = wow.writeCompanion(root, ["..", "Data"], [entry]);
  assert.ok(res.every((r) => !r.ok));
});
test("skips broken entries", () => {
  const lua = wow.buildLua([entry, { token: "NOPE", specIndex: 1, name: "x", rotation: rot }, { token: "MAGE", specIndex: 9, name: "y", rotation: rot }]);
  assert.strictEqual((lua.match(/class = /g) || []).length, 1);
});

fs.rmSync(root, { recursive: true, force: true });
if (failed) { console.log(failed + " FAILED"); process.exit(1); }
console.log("ALL PASS");
