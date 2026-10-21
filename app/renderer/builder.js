// RCRotations Workshop: "Build a new rotation" tab. Pick a class and spec, drag
// spells into the priority list, add simple conditions, save to WoW.
(function () {
  "use strict";
  const $ = (id) => document.getElementById(id);
  let W = null;            // window.RCW from app.js
  let build = null;        // the rotation being built
  let palette = [];        // [{ id, channel }]
  let dragLine = null;     // index of the line being dragged

  const store = {
    get(k) { try { const v = localStorage.getItem("rcw:" + k); return v ? JSON.parse(v) : null; } catch (e) { return null; } },
    set(k, v) { try { localStorage.setItem("rcw:" + k, JSON.stringify(v)); } catch (e) {} },
  };

  // ---------------------------------------------------------------- conditions
  const RES = [
    ["mana", "Mana %", { currentManaPercent: {} }, true],
    ["generic", "Class resource (holy power, shards, orbs, fury, embers)", { currentGenericResource: {} }],
    ["rage", "Rage", { currentRage: {} }], ["energy", "Energy", { currentEnergy: {} }], ["focus", "Focus", { currentFocus: {} }],
    ["runic", "Runic power", { currentRunicPower: {} }], ["combo", "Combo points", { currentComboPoints: {} }], ["chi", "Chi", { monkCurrentChi: {} }],
  ];
  const TYPES = [
    { t: "buffDown", label: "My buff is missing", spell: true },
    { t: "buffUp", label: "My buff is up", spell: true },
    { t: "buffStacks", label: "My buff has at least … stacks", spell: true, n: 5 },
    { t: "dotMissing", label: "My debuff is missing on the target", spell: true },
    { t: "dotLow", label: "My debuff has less than … sec left", spell: true, n: 3 },
    { t: "tgtDebuffDown", label: "Target is missing a debuff (from anyone)", spell: true },
    { t: "res", label: "Resource", res: true, n: 50 },
    { t: "thp", label: "Target health below … %", n: 35 },
    { t: "php", label: "My health below … %", n: 40 },
    { t: "targets", label: "At least … targets", n: 3 },
    { t: "cdReady", label: "Another spell is ready", spell: true },
    { t: "cdBusy", label: "Another spell is on cooldown", spell: true },
    { t: "moving", label: "I'm moving" },
    { t: "still", label: "I'm standing still" },
    { t: "combat", label: "Fight has lasted at least … sec", n: 5 },
  ];
  const typeOf = (t) => TYPES.find((x) => x.t === t) || TYPES[0];
  const sid = (id) => ({ spellId: id });
  const cmp = (op, lhs, rhs) => ({ cmp: { op, lhs, rhs } });
  const k = (v) => ({ const: { val: String(v) } });

  function compileCond(c) {
    const n = Number(c.n) || 0;
    switch (c.t) {
      case "buffUp": return { auraIsActive: { auraId: sid(c.spell) } };
      case "buffDown": return { auraIsInactive: { auraId: sid(c.spell) } };
      case "buffStacks": return cmp("OpGe", { auraNumStacks: { auraId: sid(c.spell) } }, k(n));
      case "dotMissing": return { not: { val: { dotIsActive: { spellId: sid(c.spell) } } } };
      case "dotLow": return cmp("OpLt", { dotRemainingTime: { spellId: sid(c.spell) } }, k(n + "s"));
      case "tgtDebuffDown": return { auraIsInactive: { auraId: sid(c.spell), sourceUnit: { type: "CurrentTarget" } } };
      case "res": {
        const r = RES.find((x) => x[0] === c.res) || RES[0];
        return cmp(c.op === "le" ? "OpLe" : "OpGe", r[2], k(r[3] ? n + "%" : n));
      }
      case "thp": return cmp("OpLt", { currentHealthPercent: { sourceUnit: { type: "CurrentTarget" } } }, k(n + "%"));
      case "php": return cmp("OpLt", { currentHealthPercent: {} }, k(n + "%"));
      case "targets": return cmp("OpGe", { numberTargets: {} }, k(n));
      case "cdReady": return { spellIsReady: { spellId: sid(c.spell) } };
      case "cdBusy": return { not: { val: { spellIsReady: { spellId: sid(c.spell) } } } };
      case "moving": return { unitIsMoving: {} };
      case "still": return { not: { val: { unitIsMoving: {} } } };
      case "combat": return cmp("OpGe", { currentTime: {} }, k(n + "s"));
      default: return null;
    }
  }
  function condReady(c) { return !typeOf(c.t).spell || Number(c.spell) > 0; }
  function compile() {
    return {
      type: "TypeAPL",
      prepullActions: [],
      priorityList: build.lines.map((l) => {
        const action = {};
        const conds = (l.conds || []).filter(condReady).map(compileCond).filter(Boolean);
        if (conds.length === 1) action.condition = conds[0];
        else if (conds.length > 1) action.condition = { and: { vals: conds } };
        action[l.channel ? "channelSpell" : "castSpell"] = { spellId: sid(l.spell) };
        return { action };
      }),
    };
  }

  // ---------------------------------------------------------------- spells for a spec
  function specPalette(token, idx) {
    const found = new Map();
    const walk = (a) => {
      if (!a || typeof a !== "object") return;
      if (Array.isArray(a)) { a.forEach(walk); return; }
      for (const key of ["castSpell", "channelSpell", "multidot", "strictMultidot"]) {
        const id = a[key] && a[key].spellId && a[key].spellId.spellId;
        if (id && !found.has(id)) found.set(id, key === "channelSpell");
      }
      Object.values(a).forEach(walk);
    };
    W.rots().filter((r) => r.token === token && r.specIndex === idx).forEach((r) => walk(r.rotation));
    const list = [...found.entries()].map(([id, channel]) => ({ id, channel }));
    const count = {};
    list.forEach((p) => { count[nameOf(p.id)] = (count[nameOf(p.id)] || 0) + 1; });
    list.forEach((p) => { p.label = count[nameOf(p.id)] > 1 ? nameOf(p.id) + " (" + p.id + ")" : nameOf(p.id); });
    return list.sort((a, b) => a.label.localeCompare(b.label));
  }
  const nameOf = (id) => W.names().spells[id] || ("Spell " + id);
  function idFromText(txt) {
    txt = String(txt || "").trim();
    const n = parseInt(txt, 10);
    if (n > 0 && String(n) === txt) return n;
    const hit = Object.entries(W.names().spells).find(([, nm]) => nm.toLowerCase() === txt.toLowerCase());
    return hit ? parseInt(hit[0], 10) : 0;
  }

  // ---------------------------------------------------------------- state
  function newBuild(token, specIndex, cls) {
    return { id: "b" + Date.now(), name: "My rotation", cls, token, specIndex, lines: [] };
  }
  function saveLocal() {
    const all = store.get("builds") || [];
    const i = all.findIndex((b) => b.id === build.id);
    if (i >= 0) all[i] = build; else all.push(build);
    store.set("builds", all);
    store.set("buildLast", build.id);
  }

  // ---------------------------------------------------------------- render
  function specOptions(selected) {
    // MoP specs, plus "WoW Forever" (no specs; spec 0) for classes Forever has.
    const forever = new Set(W.rots().filter((r) => r.specIndex === 0).map((r) => r.cls));
    return Object.keys(W.SPECS).map((c) => {
      const opts = W.SPECS[c].map((s, i) => [W.CLASS[c][2] + "|" + (i + 1) + "|" + c, W.CLASS[c][0] + " · " + W.pretty(s)]);
      if (forever.has(c)) opts.push([W.CLASS[c][2] + "|0|" + c, W.CLASS[c][0] + " · WoW Forever"]);
      return opts.map(([v, label]) => `<option value="${v}" ${selected === v ? "selected" : ""}>${W.esc(label)}</option>`).join("");
    }).join("");
  }
  function render() {
    const e = W.esc;
    const builds = store.get("builds") || [];
    const specVal = build.token + "|" + build.specIndex + "|" + build.cls;
    palette = specPalette(build.token, build.specIndex);
    $("builder").innerHTML = `
      <aside class="palette" aria-label="Spells">
        <div class="label">Class and spec</div>
        <select id="bSpec" aria-label="Class and spec">${specOptions(specVal)}</select>
        <div class="label">Spells</div>
        <input type="text" id="bSearch" placeholder="Search spells" aria-label="Search spells">
        <div class="spells" id="bSpells">${palette.map((p) => `<div class="spellchip" draggable="true" data-sp="${p.id}" data-ch="${p.channel ? 1 : 0}"><span>${e(p.label)}</span><button data-add="${p.id}" data-ch="${p.channel ? 1 : 0}" aria-label="Add ${e(p.label)}" title="Add to the bottom">+</button></div>`).join("") || '<p class="sub">No spells known for this spec yet. Add one by name or ID below.</p>'}</div>
        <div class="row"><input type="text" id="bOther" list="spellNames" placeholder="Other spell (name or ID)" aria-label="Other spell"><button class="btn" id="bOtherAdd">Add</button></div>
        <p class="sub">Drag spells into the rotation, or click +. Spells come from the rotations for this spec (WoWSims, or the Forever Rotation lists for WoW Forever).</p>
      </aside>
      <div class="canvas">
        <div class="head">
          <div style="display:grid;gap:6px;min-width:0">
            <div class="row">
              <input type="text" id="bName" maxlength="40" value="${e(build.name)}" aria-label="Rotation name">
              <select id="bPick" aria-label="Your builds">
                ${builds.map((b) => `<option value="${e(b.id)}" ${b.id === build.id ? "selected" : ""}>${e(b.name)} (${e(W.specLabel(b.token, b.specIndex))})</option>`).join("")}
              </select>
              <button class="btn" id="bNew">New</button>
              <button class="btn danger" id="bDel">Delete</button>
            </div>
            <div class="sub">Top to bottom: RCRotations suggests the first spell whose conditions all pass and that you can cast.</div>
          </div>
          <div class="actions">
            <button class="btn primary" id="bSave">Save to WoW</button>
            <button class="btn" id="bCopy">Copy for /rcr import</button>
          </div>
        </div>
        <div class="drop" id="bDrop" aria-label="Rotation">
          ${build.lines.length ? build.lines.map(lineHTML).join("") : '<div class="empty">Drag spells here to build your rotation.</div>'}
        </div>
      </div>`;
    wire();
  }
  function condHTML(c, li, ci) {
    const e = W.esc, ty = typeOf(c.t);
    let extra = "";
    if (ty.res) {
      extra += `<select data-f="res" aria-label="Resource">${RES.map((r) => `<option value="${r[0]}" ${c.res === r[0] ? "selected" : ""}>${e(r[1])}</option>`).join("")}</select>`;
      extra += `<select data-f="op" aria-label="Compare"><option value="ge" ${c.op !== "le" ? "selected" : ""}>at least</option><option value="le" ${c.op === "le" ? "selected" : ""}>at most</option></select>`;
    }
    if (ty.spell) extra += `<input type="text" data-f="spell" list="spellNames" placeholder="Spell name or ID" value="${c.spell ? e(nameOf(c.spell)) : ""}" aria-label="Spell for this condition">`;
    if (ty.n !== undefined) extra += `<input type="number" data-f="n" value="${e(c.n !== undefined ? c.n : ty.n)}" aria-label="Number">`;
    const warn = ty.spell && !(Number(c.spell) > 0) ? '<span class="err">pick a spell</span>' : "";
    return `<div class="cond-row" data-li="${li}" data-ci="${ci}">${ci ? '<span class="cond-and">and</span>' : '<span class="cond-and">when</span>'}
      <select data-f="t" aria-label="Condition">${TYPES.map((t) => `<option value="${t.t}" ${t.t === c.t ? "selected" : ""}>${e(t.label)}</option>`).join("")}</select>${extra}${warn}
      <button data-rmc aria-label="Remove condition" title="Remove condition">×</button></div>`;
  }
  function lineHTML(l, i) {
    const e = W.esc;
    return `<div class="bline" draggable="true" data-li="${i}">
      <div class="bhead"><span class="grip" title="Drag to move">⋮⋮</span><span class="num">${i + 1}</span>
        <span class="nm">${e(nameOf(l.spell))}${l.channel ? '<span class="kind">channel</span>' : ""}</span>
        <button data-up aria-label="Move up" title="Move up">↑</button><button data-down aria-label="Move down" title="Move down">↓</button><button data-rml aria-label="Remove spell" title="Remove spell">×</button></div>
      <div class="conds">${(l.conds || []).map((c, ci) => condHTML(c, i, ci)).join("") || '<span class="sub">Always, whenever it\'s castable.</span>'}
        <button class="addcond" data-addc>+ Add a condition</button></div>
    </div>`;
  }

  // ---------------------------------------------------------------- events
  function addLine(id, channel, at) {
    const line = { spell: id, channel: !!channel, conds: [] };
    if (at === undefined || at < 0 || at > build.lines.length) build.lines.push(line); else build.lines.splice(at, 0, line);
    saveLocal(); render();
  }
  function dropIndex(ev) {
    const lines = [...document.querySelectorAll("#bDrop .bline")];
    for (let i = 0; i < lines.length; i++) {
      const r = lines[i].getBoundingClientRect();
      if (ev.clientY < r.top + r.height / 2) return i;
    }
    return lines.length;
  }
  function wire() {
    const drop = $("bDrop");
    $("bSpec").onchange = () => {
      const [token, idx, cls] = $("bSpec").value.split("|");
      build.token = token; build.specIndex = +idx; build.cls = cls;
      saveLocal(); render();
    };
    $("bSearch").oninput = () => {
      const q = $("bSearch").value.trim().toLowerCase();
      document.querySelectorAll("#bSpells .spellchip").forEach((el) => { el.hidden = q && !el.textContent.toLowerCase().includes(q); });
    };
    $("bSpells").addEventListener("click", (ev) => {
      const b = ev.target.closest("[data-add]"); if (b) addLine(+b.dataset.add, b.dataset.ch === "1");
    });
    $("bSpells").addEventListener("dragstart", (ev) => {
      const chip = ev.target.closest(".spellchip"); if (!chip) return;
      ev.dataTransfer.setData("text/rc-spell", chip.dataset.sp + "|" + chip.dataset.ch);
      ev.dataTransfer.effectAllowed = "copy";
    });
    $("bOtherAdd").onclick = () => {
      const id = idFromText($("bOther").value);
      if (!id) { W.toast("Type a spell ID (the number in a Wowhead link) or pick a name from the list"); return; }
      addLine(id, false);
    };
    $("bName").onchange = () => { build.name = $("bName").value.trim() || "My rotation"; saveLocal(); render(); };
    $("bPick").onchange = () => { const b = (store.get("builds") || []).find((x) => x.id === $("bPick").value); if (b) { build = b; store.set("buildLast", b.id); render(); } };
    $("bNew").onclick = () => { build = newBuild(build.token, build.specIndex, build.cls); saveLocal(); render(); $("bName").focus(); $("bName").select(); };
    $("bDel").onclick = (ev) => {
      const b = ev.currentTarget;
      if (!b.dataset.sure) { b.dataset.sure = "1"; b.textContent = "Click again to delete"; return; }
      const all = (store.get("builds") || []).filter((x) => x.id !== build.id);
      store.set("builds", all);
      build = all[all.length - 1] || newBuild(build.token, build.specIndex, build.cls);
      saveLocal(); render(); W.toast("Deleted from the app. Anything already saved to WoW stays until you remove it there.");
    };
    $("bSave").onclick = async () => {
      if (!build.lines.length) { W.toast("Add at least one spell first"); return; }
      const res = await window.rc.savePut({ token: build.token, specIndex: build.specIndex, name: build.name, rotation: compile() });
      if (res.saved) W.setSaved(res.saved);
      W.toast(res.ok ? `Saved "${build.name}". Type /reload in game, then pick it with /rcr apl.` : (res.error || "Couldn't save."));
    };
    $("bCopy").onclick = async () => {
      try { await navigator.clipboard.writeText(JSON.stringify(compile())); W.toast("Copied. Paste it in game with /rcr import"); }
      catch (e) { W.toast("Couldn't copy to the clipboard"); }
    };

    // drop zone: new spells and reordering
    drop.addEventListener("dragover", (ev) => {
      ev.preventDefault(); drop.classList.add("over");
      document.querySelectorAll("#bDrop .bline").forEach((el, i) => el.classList.toggle("overline", i === dropIndex(ev)));
    });
    drop.addEventListener("dragleave", (ev) => { if (!drop.contains(ev.relatedTarget)) { drop.classList.remove("over"); document.querySelectorAll(".overline").forEach((el) => el.classList.remove("overline")); } });
    drop.addEventListener("drop", (ev) => {
      ev.preventDefault(); drop.classList.remove("over");
      const at = dropIndex(ev);
      const sp = ev.dataTransfer.getData("text/rc-spell");
      if (sp) { const [id, ch] = sp.split("|"); addLine(+id, ch === "1", at); return; }
      if (dragLine !== null) {
        const [moved] = build.lines.splice(dragLine, 1);
        build.lines.splice(at > dragLine ? at - 1 : at, 0, moved);
        dragLine = null; saveLocal(); render();
      }
    });
    drop.addEventListener("dragstart", (ev) => {
      const line = ev.target.closest(".bline"); if (!line || ev.target.closest("input,select")) return;
      dragLine = +line.dataset.li; line.classList.add("dragging");
      ev.dataTransfer.setData("text/rc-line", String(dragLine)); ev.dataTransfer.effectAllowed = "move";
    });
    drop.addEventListener("dragend", () => { dragLine = null; render(); });

    // line + condition controls
    drop.addEventListener("click", (ev) => {
      const line = ev.target.closest(".bline"); if (!line) return;
      const i = +line.dataset.li, L = build.lines;
      if (ev.target.closest("[data-up]") && i > 0) [L[i - 1], L[i]] = [L[i], L[i - 1]];
      else if (ev.target.closest("[data-down]") && i < L.length - 1) [L[i + 1], L[i]] = [L[i], L[i + 1]];
      else if (ev.target.closest("[data-rml]")) L.splice(i, 1);
      else if (ev.target.closest("[data-addc]")) (L[i].conds = L[i].conds || []).push({ t: "buffDown", n: undefined });
      else if (ev.target.closest("[data-rmc]")) L[i].conds.splice(+ev.target.closest(".cond-row").dataset.ci, 1);
      else return;
      saveLocal(); render();
    });
    drop.addEventListener("change", (ev) => {
      const row = ev.target.closest(".cond-row"); if (!row) return;
      const c = build.lines[+row.dataset.li].conds[+row.dataset.ci];
      const f = ev.target.dataset.f;
      if (f === "t") { c.t = ev.target.value; delete c.n; if (!typeOf(c.t).spell) delete c.spell; if (typeOf(c.t).res && !c.res) { c.res = "mana"; c.op = "ge"; } }
      else if (f === "spell") { c.spell = idFromText(ev.target.value); if (!c.spell) W.toast("Couldn't find that spell. Use a name from the list or the spell ID."); }
      else if (f === "n") c.n = Number(ev.target.value);
      else if (f === "res") c.res = ev.target.value;
      else if (f === "op") c.op = ev.target.value;
      saveLocal(); render();
    });
  }

  // ---------------------------------------------------------------- tabs
  function showTab(which) {
    $("tabEdit").setAttribute("aria-selected", which === "edit");
    $("tabBuild").setAttribute("aria-selected", which === "build");
    $("editorApp").hidden = which !== "edit";
    $("builder").hidden = which !== "build";
    store.set("tab", which);
    if (which === "build") render();
  }
  $("tabEdit").onclick = () => showTab("edit");
  $("tabBuild").onclick = () => showTab("build");

  document.addEventListener("rcw-ready", () => {
    W = window.RCW;
    const builds = store.get("builds") || [];
    build = builds.find((b) => b.id === store.get("buildLast")) || builds[builds.length - 1] || newBuild("WARLOCK", 2, "warlock");
    if (store.get("tab") === "build") showTab("build");
  });
  window.RCBuilder = { compile: () => compile(), compileCond };
})();
