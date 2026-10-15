// RCRotations Workshop: renderer. Talks to the main process through window.rc (preload.js).
(function () {
  "use strict";
  const CLASS = {
    death_knight: ["Death Knight", "#C41E3A", "DEATHKNIGHT"], druid: ["Druid", "#FF7C0A", "DRUID"], hunter: ["Hunter", "#AAD372", "HUNTER"],
    mage: ["Mage", "#3FC7EB", "MAGE"], monk: ["Monk", "#00FF98", "MONK"], paladin: ["Paladin", "#F48CBA", "PALADIN"],
    priest: ["Priest", "#BBBBBB", "PRIEST"], rogue: ["Rogue", "#FFF468", "ROGUE"], shaman: ["Shaman", "#0070DD", "SHAMAN"],
    warlock: ["Warlock", "#8788EE", "WARLOCK"], warrior: ["Warrior", "#C69B6D", "WARRIOR"],
  };
  const SPECS = {
    death_knight: ["blood", "frost", "unholy"], druid: ["balance", "feral", "guardian", "restoration"],
    hunter: ["beast_mastery", "marksmanship", "survival"], mage: ["arcane", "fire", "frost"],
    monk: ["brewmaster", "mistweaver", "windwalker"], paladin: ["holy", "protection", "retribution"],
    priest: ["discipline", "holy", "shadow"], rogue: ["assassination", "combat", "subtlety"],
    shaman: ["elemental", "enhancement", "restoration"], warlock: ["affliction", "demonology", "destruction"],
    warrior: ["arms", "fury", "protection"],
  };
  const OPS = { OpLt: "<", OpLe: "≤", OpGt: ">", OpGe: "≥", OpEq: "=", OpNe: "≠" };
  const MATH = { OpAdd: "+", OpSub: "−", OpMul: "×", OpDiv: "÷" };
  let ROTS = [], NAMES = { spells: {}, items: {} }, SAVED = [], current = null, work = null, cls = null;
  const $ = (id) => document.getElementById(id);
  const esc = (s) => String(s).replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]));
  const clone = (o) => JSON.parse(JSON.stringify(o));
  const pretty = (s) => s.replace(/_/g, " ").replace(/\b\w/g, (c) => c.toUpperCase());
  const store = {
    get(k) { try { const v = localStorage.getItem("rcw:" + k); return v ? JSON.parse(v) : null; } catch (e) { return null; } },
    set(k, v) { try { localStorage.setItem("rcw:" + k, JSON.stringify(v)); } catch (e) {} },
    del(k) { try { localStorage.removeItem("rcw:" + k); } catch (e) {} },
  };

  function toast(msg) {
    const t = $("toast"); t.textContent = msg; t.hidden = false;
    clearTimeout(toast._t); toast._t = setTimeout(() => (t.hidden = true), 2600);
  }

  // ---------------------------------------------------------------- names / text
  function idName(ref) {
    if (!ref || typeof ref !== "object") return "?";
    if (ref.spellId) return NAMES.spells[ref.spellId] || ("Spell " + ref.spellId);
    if (ref.itemId) return NAMES.items[ref.itemId] || ("Item " + ref.itemId);
    if (ref.otherId) return ({ OtherActionPotion: "Potion" })[ref.otherId] || String(ref.otherId).replace(/^OtherAction/, "");
    return "?";
  }
  function idLink(ref) {
    const n = esc(idName(ref));
    if (ref && ref.spellId) return `<a href="https://www.wowhead.com/mop-classic/spell=${ref.spellId}" target="_blank" rel="noopener">${n}</a>`;
    if (ref && ref.itemId) return `<a href="https://www.wowhead.com/mop-classic/item=${ref.itemId}" target="_blank" rel="noopener">${n}</a>`;
    return n;
  }
  const unitPre = (u) => (u && u.type && u.type !== "Self" && u.type !== "Player") ? (u.type === "CurrentTarget" || u.type === "Target" ? "target " : u.type.toLowerCase() + " ") : "";
  const words = (k) => k.replace(/([A-Z])/g, " $1").toLowerCase().trim();

  function val(v, top) {
    if (!v || typeof v !== "object") return "?";
    const k = Object.keys(v)[0]; const b = v[k] || {};
    const wrap = (s) => (top ? s : "(" + s + ")");
    const list = (xs, sep) => { xs = (xs || []).filter((x) => x && Object.keys(x).length); return xs.length === 1 ? val(xs[0], top) : wrap(xs.map((x) => val(x)).join(sep)); };
    switch (k) {
      case "and": return list(b.vals, " and ");
      case "or": return list(b.vals, " or ");
      case "not": return "not " + val(b.val);
      case "cmp": return wrap(val(b.lhs, true) + " " + (OPS[b.op] || b.op) + " " + val(b.rhs, true));
      case "math": return "(" + val(b.lhs, true) + " " + (MATH[b.op] || b.op) + " " + val(b.rhs, true) + ")";
      case "max": return "max(" + (b.vals || []).map((x) => val(x, true)).join(", ") + ")";
      case "min": return "min(" + (b.vals || []).map((x) => val(x, true)).join(", ") + ")";
      case "const": return String(b.val);
      case "variableRef": return "[" + b.name + "]";
      case "auraIsActive": return unitPre(b.sourceUnit) + idName(b.auraId) + " up";
      case "auraIsInactive": return unitPre(b.sourceUnit) + idName(b.auraId) + " down";
      case "auraRemainingTime": return unitPre(b.sourceUnit) + idName(b.auraId) + " time left";
      case "auraNumStacks": return unitPre(b.sourceUnit) + idName(b.auraId) + " stacks";
      case "auraIsKnown": return "has " + idName(b.auraId);
      case "auraShouldRefresh": return idName(b.auraId) + " needs refresh";
      case "auraInternalCooldown": return idName(b.auraId) + " internal cooldown";
      case "dotIsActive": return idName(b.spellId) + " on target";
      case "dotRemainingTime": return idName(b.spellId) + " left on target";
      case "dotPercentIncrease": return idName(b.spellId) + " snapshot gain";
      case "dotTickFrequency": return idName(b.spellId) + " tick time";
      case "dotBaseDuration": return idName(b.spellId) + " base duration";
      case "spellCanCast": return idName(b.spellId) + " castable";
      case "spellIsReady": return idName(b.spellId) + " ready";
      case "spellIsKnown": return "knows " + idName(b.spellId);
      case "spellTimeToReady": return idName(b.spellId) + " cooldown";
      case "spellNumCharges": return idName(b.spellId) + " charges";
      case "spellTimeToCharge": return idName(b.spellId) + " next charge";
      case "spellCastTime": return idName(b.spellId) + " cast time";
      case "spellGcdHastedDuration": return idName(b.spellId) + " GCD";
      case "currentTime": return "fight time";
      case "currentTimePercent": return "fight %";
      case "remainingTime": return "time left in fight";
      case "remainingTimePercent": return "fight % left";
      case "isExecutePhase": return "target below " + String(b.threshold || "").replace(/^E/, "") + "%";
      case "numberTargets": return "targets";
      case "currentHealthPercent": return unitPre(b.sourceUnit) + "health %";
      case "currentManaPercent": return "mana %";
      case "currentMana": return "mana";
      case "currentGenericResource": return "class resource";
      case "currentRunicPower": return "runic power";
      case "maxRunicPower": return "max runic power";
      case "currentRuneCount": return String(b.runeType || "").replace(/^Rune/, "").toLowerCase() + " runes";
      case "currentNonDeathRuneCount": return "non-death " + String(b.runeType || "").replace(/^Rune/, "").toLowerCase() + " runes";
      case "currentEnergy": return "energy";
      case "currentRage": return "rage";
      case "currentFocus": return "focus";
      case "currentComboPoints": return "combo points";
      case "monkCurrentChi": return "chi";
      case "gcdIsReady": return "GCD ready";
      case "gcdTimeToReady": return "GCD left";
      case "unitIsMoving": return "moving";
      case "bossCurrentTarget": return "boss is targeting me";
      default: return words(k);
    }
  }

  function actionInfo(a) {
    const k = Object.keys(a).find((x) => x !== "condition");
    const b = (k && a[k]) || {};
    const cancel = (ref) => (ref && ref.spellId === 103958 && ref.tag === 1 ? " (cancel)" : "");
    switch (k) {
      case "castSpell": return { what: idLink(b.spellId) + cancel(b.spellId), kind: "" };
      case "castFriendlySpell": return { what: idLink(b.spellId), kind: "on ally" };
      case "channelSpell": return { what: idLink(b.spellId), kind: "channel" };
      case "multidot": case "strictMultidot": return { what: idLink(b.spellId), kind: "keep up" };
      case "multishield": return { what: idLink(b.spellId), kind: "shields" };
      case "groupReference": return { what: esc(b.groupName), kind: "group", group: b.groupName };
      case "autocastOtherCooldowns": return { what: "Other cooldowns", kind: "trinkets, racials" };
      case "wait": case "waitUntil": return { what: "Wait", kind: "hold" };
      case "sequence": case "strictSequence": return { what: (b.actions || []).map((x) => actionInfo(x).what).join(" → "), kind: "sequence" };
      case "schedule": return { what: actionInfo(b.innerAction || {}).what, kind: "timed" };
      default: return { what: esc(words(k || "unknown")), kind: "" };
    }
  }

  // ---------------------------------------------------------------- WoW folder bar
  async function renderWow(state) {
    state = state || await window.rc.wowState();
    $("wowPath").textContent = state.root || "No WoW folder chosen yet";
    $("wowBtn").textContent = state.root ? "Change WoW folder" : "Choose WoW folder";
    if (state.error) toast(state.error);
    if (!state.root) { $("flavors").innerHTML = ""; return; }
    if (!state.flavors.length) { $("flavors").innerHTML = '<span class="status warn">No game versions found in that folder.</span>'; return; }
    $("flavors").innerHTML = '<span class="label">Save to</span>' + state.flavors.map((f) =>
      `<label class="flv"><input type="checkbox" data-flv="${esc(f.dir)}" ${state.chosen.includes(f.dir) ? "checked" : ""}>${esc(f.label)}${f.hasAddon ? "" : ' <span class="status">(RCRotations not installed)</span>'}</label>`).join("");
  }
  $("wowBtn").onclick = async () => renderWow(await window.rc.chooseWow());
  $("flavors").addEventListener("change", async () => {
    const list = [...document.querySelectorAll("[data-flv]")].filter((x) => x.checked).map((x) => x.dataset.flv);
    renderWow(await window.rc.setFlavors(list));
  });

  // ---------------------------------------------------------------- library
  function renderChips() {
    const classes = [...new Set(ROTS.map((r) => r.cls))];
    $("classChips").innerHTML = classes.map((c) => `<button class="chip" data-c="${c}" aria-pressed="${c === cls}"><i style="background:${CLASS[c] ? CLASS[c][1] : "#999"}"></i>${esc(CLASS[c] ? CLASS[c][0] : c)}</button>`).join("");
  }
  function renderList() {
    const mine = store.get("mine") || [];
    const show = ROTS.map((r, i) => ({ r, i })).filter((x) => x.r.cls === cls);
    const specs = [...new Set(show.map((x) => x.r.spec))];
    let html = specs.map((s) => `<div class="spec"><h3>${esc(pretty(s))}</h3>${show.filter((x) => x.r.spec === s).map((x) => {
      const edited = store.get("edit:" + x.r.file);
      return `<button class="rot" data-i="${x.i}" aria-current="${!!current && current.file === x.r.file}"><span>${esc(x.r.name)}</span>${edited ? '<span class="tag">edited</span>' : ""}</button>`;
    }).join("")}</div>`).join("");
    const mineHere = mine.map((m, j) => ({ m, j })).filter((x) => x.m.cls === cls);
    if (mineHere.length) html += `<div class="spec"><h3>Your exports</h3>${mineHere.map((x) => `<button class="rot" data-m="${x.j}" aria-current="${!!current && current.file === x.m.file}"><span>${esc(x.m.name)}</span><span class="tag">yours</span></button>`).join("")}</div>`;
    $("rotList").innerHTML = html || '<p class="sub">No rotations for this class.</p>';
  }
  function specLabel(token, idx) {
    const c = Object.keys(CLASS).find((k) => CLASS[k][2] === token);
    return c ? CLASS[c][0] + " · " + pretty(SPECS[c][idx - 1] || "") : token;
  }
  function renderSaved() {
    if (!SAVED.length) { $("savedList").innerHTML = '<p class="sub">Nothing saved yet.</p>'; return; }
    $("savedList").innerHTML = SAVED.map((s, i) => `<div class="savedrow"><div><b>${esc(s.name)}</b><small>${esc(specLabel(s.token, s.specIndex))}</small></div><button data-rm="${i}" aria-label="Remove ${esc(s.name)} from WoW" title="Remove from WoW">×</button></div>`).join("");
  }
  $("savedList").addEventListener("click", async (e) => {
    const b = e.target.closest("[data-rm]"); if (!b) return;
    const s = SAVED[+b.dataset.rm];
    if (!b.dataset.sure) { b.dataset.sure = "1"; b.textContent = "?"; b.title = "Click again to remove"; return; }
    const res = await window.rc.saveRemove({ token: s.token, specIndex: s.specIndex, name: s.name });
    SAVED = res.saved || SAVED; renderSaved();
    toast(res.ok ? "Removed. /reload in game to update your list." : res.error);
  });

  // ---------------------------------------------------------------- editor
  function open(rot) {
    current = rot;
    work = store.get("edit:" + rot.file) || clone(rot.rotation);
    store.set("last", rot.file);
    if (rot.cls) { cls = rot.cls; renderChips(); }
    renderList(); renderMain();
  }
  function save() { store.set("edit:" + current.file, work); renderList(); }
  function listOf(id) {
    if (id === "main") return work.priorityList || (work.priorityList = []);
    const g = (work.groups || []).find((x) => "g:" + x.name === id);
    return g ? (g.actions || (g.actions = [])) : [];
  }
  function exportRotation() {
    const out = { type: "TypeAPL" };
    for (const k of ["prepullActions", "priorityList", "groups", "valueVariables"]) if (work[k]) out[k] = work[k];
    return out;
  }
  function lineHTML(item, idx, listId) {
    const a = item.action || {};
    const info = actionInfo(a);
    const cond = a.condition && Object.keys(a.condition).length ? esc(val(a.condition, true)) : "";
    let html = `<div class="line${item.hide ? " off" : ""}" data-list="${esc(listId)}" data-idx="${idx}">
      <span class="num">${idx + 1}</span>
      <div style="min-width:0"><div class="what">${info.what}${info.kind ? `<span class="kind">${esc(info.kind)}</span>` : ""}</div>
      <div class="cond${cond ? "" : " none"}">${cond ? "when " + cond : "always, when castable"}</div></div>
      <div class="tools">
        <input type="checkbox" ${item.hide ? "" : "checked"} data-act="toggle" aria-label="Use this line" title="Use this line">
        <button data-act="up" aria-label="Move up" title="Move up">↑</button>
        <button data-act="down" aria-label="Move down" title="Move down">↓</button>
        <button data-act="json" aria-label="Edit line" title="Edit line">{ }</button>
        <button data-act="del" aria-label="Remove line" title="Remove line">×</button>
      </div>`;
    if (info.group) {
      const g = (work.groups || []).find((x) => x.name === info.group);
      if (g) html += `<div class="group">${(g.actions || []).map((it, j) => lineHTML(it, j, "g:" + info.group)).join("")}</div>`;
    }
    return html + "</div>";
  }
  function renderMain() {
    if (!current) { $("main").innerHTML = '<p class="sub">Pick a rotation on the left.</p>'; return; }
    const edited = !!store.get("edit:" + current.file);
    const n = (work.priorityList || []).length;
    const defName = current.mine ? current.name : "My " + current.name;
    $("main").innerHTML = `
      <div class="head">
        <div><div class="sub">${esc(specLabel(current.token, current.specIndex))}</div><h2>${esc(current.name)}</h2><div class="sub">${n} lines, top to bottom. The first line whose condition passes is what RCRotations suggests.</div></div>
        <div class="actions">
          <button class="btn primary" id="saveBtn">Save to WoW</button>
          <button class="btn" id="copyBtn">Copy for /rcr import</button>
          <button class="btn danger" id="resetBtn" ${edited && !current.mine ? "" : "hidden"}>Reset to WoWSims</button>
        </div>
      </div>
      <div class="savepanel" id="savePanel" hidden>
        <div class="row"><label for="saveName" class="label">Name in game</label>
        <input type="text" id="saveName" maxlength="40" value="${esc(defName)}">
        <button class="btn primary" id="saveGo">Save</button><button class="btn" id="saveCancel">Cancel</button></div>
        <div class="sub">Saved for ${esc(specLabel(current.token, current.specIndex))}. Saving again with the same name replaces it.</div>
        <div id="saveMsg" aria-live="polite"></div>
      </div>
      <div class="stack">${(work.priorityList || []).map((it, i) => lineHTML(it, i, "main")).join("")}</div>
      <details class="box"><summary>Add a spell</summary>
        <div class="row"><input type="text" id="addId" list="spellNames" placeholder="Spell name or ID" aria-label="Spell name or ID">
        <button class="btn" id="addBtn">Add at the bottom</button></div>
        <p class="sub">The new line has no condition, so it's used whenever it's castable. Use { } on the line to add one.</p>
        <div id="addMsg" aria-live="polite"></div>
      </details>`;
    $("saveBtn").onclick = () => { $("savePanel").hidden = false; $("saveName").focus(); $("saveName").select(); };
    $("saveCancel").onclick = () => { $("savePanel").hidden = true; };
    $("saveGo").onclick = async () => {
      const name = $("saveName").value.trim();
      if (!name) { $("saveMsg").innerHTML = '<span class="err">Give it a name.</span>'; return; }
      const res = await window.rc.savePut({ token: current.token, specIndex: current.specIndex, name, rotation: exportRotation() });
      if (res.saved) { SAVED = res.saved; renderSaved(); }
      if (res.ok) { $("savePanel").hidden = true; toast("Saved \"" + name + "\". Type /reload in game, then pick it with /rcr apl."); }
      else $("saveMsg").innerHTML = `<span class="err">${esc(res.error || "Couldn't save.")}</span>` + (res.saved ? ' <span class="sub">It\'s kept in the app; it goes into WoW once the folder is set.</span>' : "");
    };
    $("copyBtn").onclick = async () => {
      try { await navigator.clipboard.writeText(JSON.stringify(exportRotation())); toast("Copied. Paste it in game with /rcr import"); }
      catch (e) { toast("Couldn't copy to the clipboard"); }
    };
    $("resetBtn").onclick = (e) => {
      const b = e.currentTarget;
      if (b.dataset.sure) { store.del("edit:" + current.file); work = clone(current.rotation); renderList(); renderMain(); toast("Back to the WoWSims version"); }
      else { b.dataset.sure = "1"; b.textContent = "Click again to reset"; }
    };
    $("addBtn").onclick = () => {
      const raw = $("addId").value.trim();
      let id = parseInt(raw, 10);
      if (!id) { const hit = Object.entries(NAMES.spells).find(([, nm]) => nm.toLowerCase() === raw.toLowerCase()); if (hit) id = parseInt(hit[0], 10); }
      if (!id) { $("addMsg").innerHTML = '<span class="err">Type a spell ID (the number in a Wowhead link) or pick a name from the list.</span>'; return; }
      work.priorityList.push({ action: { castSpell: { spellId: { spellId: id } } } });
      save(); renderMain(); toast("Added " + (NAMES.spells[id] || "spell " + id));
    };
  }
  $("main").addEventListener("click", (e) => {
    const btn = e.target.closest("[data-act]"); if (!btn || btn.dataset.act === "toggle") return;
    const line = btn.closest(".line"); const list = listOf(line.dataset.list); const i = +line.dataset.idx;
    const act = btn.dataset.act;
    if (act === "up" && i > 0) { [list[i - 1], list[i]] = [list[i], list[i - 1]]; }
    else if (act === "down" && i < list.length - 1) { [list[i + 1], list[i]] = [list[i], list[i + 1]]; }
    else if (act === "del") { list.splice(i, 1); }
    else if (act === "json") {
      const existing = line.querySelector(":scope > .json");
      if (existing) { existing.remove(); return; }
      const box = document.createElement("div"); box.className = "json";
      box.innerHTML = `<textarea aria-label="Line as WoWSims JSON">${esc(JSON.stringify(list[i].action, null, 2))}</textarea><div class="row"><button class="btn primary" data-save>Save line</button><span class="sub">WoWSims format, the same as in a wowsims.com export.</span></div><div class="err" data-err></div>`;
      line.appendChild(box);
      box.querySelector("[data-save]").onclick = (ev) => {
        ev.stopPropagation();
        try { list[i].action = JSON.parse(box.querySelector("textarea").value); save(); renderMain(); toast("Line saved"); }
        catch (err) { box.querySelector("[data-err]").textContent = "That isn't valid JSON: " + err.message; }
      };
      return;
    } else return;
    save(); renderMain();
  });
  $("main").addEventListener("change", (e) => {
    if (e.target.dataset.act !== "toggle") return;
    const line = e.target.closest(".line"); const list = listOf(line.dataset.list); const i = +line.dataset.idx;
    if (e.target.checked) delete list[i].hide; else list[i].hide = true;
    save(); renderMain();
  });
  $("classChips").addEventListener("click", (e) => { const b = e.target.closest(".chip"); if (!b) return; cls = b.dataset.c; renderChips(); renderList(); });
  $("rotList").addEventListener("click", (e) => {
    const b = e.target.closest(".rot"); if (!b) return;
    if (b.dataset.i) open(ROTS[+b.dataset.i]);
    else { const m = (store.get("mine") || [])[+b.dataset.m]; if (m) open(m); }
  });

  // ---------------------------------------------------------------- your own export
  $("pasteSpec").innerHTML = Object.keys(SPECS).map((c) => SPECS[c].map((s, i) => `<option value="${c}|${i + 1}">${esc(CLASS[c][0] + " · " + pretty(s))}</option>`).join("")).join("");
  function findRotation(d) {
    if (!d || typeof d !== "object") return null;
    if (Array.isArray(d.priorityList)) return d;
    if (d.rotation && Array.isArray(d.rotation.priorityList)) return d.rotation;
    if (d.player && d.player.rotation && Array.isArray(d.player.rotation.priorityList)) return d.player.rotation;
    return null;
  }
  function detectSpec(d) {
    const p = d && d.player; if (!p) return null;
    for (const key of Object.keys(p)) {
      for (const c of Object.keys(SPECS)) {
        const cname = CLASS[c][0].replace(/ /g, "");
        SPECS[c].forEach((s, i) => { if (key.toLowerCase() === (s.replace(/_/g, "") + cname).toLowerCase()) detectSpec.hit = c + "|" + (i + 1); });
      }
    }
    const hit = detectSpec.hit; detectSpec.hit = null; return hit;
  }
  $("pasteText").addEventListener("input", () => {
    try { const hit = detectSpec(JSON.parse($("pasteText").value)); if (hit) $("pasteSpec").value = hit; } catch (e) { /* not JSON yet */ }
  });
  $("pasteBtn").onclick = () => {
    const txt = $("pasteText").value.trim(), msg = $("pasteMsg");
    if (/^NAG_ROTATION:/.test(txt)) { msg.innerHTML = '<span class="err">That\'s a NAG rotation. The Workshop only opens WoWSims rotations.</span>'; return; }
    let d; try { d = JSON.parse(txt); } catch (e) { msg.innerHTML = '<span class="err">That isn\'t a WoWSims export. Copy the whole JSON from the Rotation tab.</span>'; return; }
    const r = findRotation(d); if (!r) { msg.innerHTML = '<span class="err">No rotation found in that text.</span>'; return; }
    const [c, idx] = $("pasteSpec").value.split("|");
    const name = $("pasteName").value.trim() || "My rotation";
    const mine = store.get("mine") || [];
    const item = { mine: true, cls: c, spec: SPECS[c][+idx - 1], token: CLASS[c][2], specIndex: +idx, name, file: "mine/" + Date.now(), rotation: r };
    mine.push(item); store.set("mine", mine);
    $("pasteText").value = ""; msg.innerHTML = '<span class="okmsg">Opened. It\'s under "Your exports" for that class.</span>';
    open(item);
  };

  // ---------------------------------------------------------------- start
  (async function boot() {
    renderWow();
    SAVED = await window.rc.savedList(); renderSaved();
    const data = await window.rc.loadData();
    ROTS = data.rotations || []; NAMES = data.names || NAMES;
    const st = $("dataStatus");
    if (data.from === "github") st.textContent = ROTS.length + " rotations, up to date from GitHub";
    else if (data.from === "cache") { st.textContent = "Offline: using rotations downloaded " + new Date(data.at).toLocaleDateString(); st.classList.add("warn"); }
    else { st.textContent = "Offline: using the rotations that came with the app"; st.classList.add("warn"); }
    const dl = document.createElement("datalist"); dl.id = "spellNames";
    dl.innerHTML = Object.entries(NAMES.spells).sort((a, b) => a[1].localeCompare(b[1])).map(([id, nm]) => `<option value="${esc(nm)}">${id}</option>`).join("");
    document.body.appendChild(dl);
    if (!ROTS.length) { $("main").innerHTML = '<p class="err">No rotations could be loaded. Check your internet connection and restart the app.</p>'; return; }
    const last = store.get("last");
    const start = ROTS.find((x) => x.file === last) || ROTS[0];
    cls = start.cls; renderChips(); open(start);
  })();
})();
