// Project library (server/projects.py): named projects in Documents/Sizzle FX, each with its
// timeline, its source video (one shared copy) and its baked masks, so a project reopens
// exactly as saved. The dialog does Save / Save as / Open / Delete, plus .json import/export.

import { serialise, deserialise } from "../project.js";
import { MaskTrack, gzip, gunzip } from "../mask/maskTrack.js";
import { fetchBlobChunked, putChunked as putWithProgress } from "../media/transfer.js";

const esc = (s) => String(s ?? "").replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]));
const enc = encodeURIComponent;

// one copy of each source video, keyed by its file name + size
export function mediaKeyOf(info) {
  const ext = (info.name.match(/\.[A-Za-z0-9]+$/) || [".mp4"])[0];
  return `${info.name.slice(0, info.name.length - ext.length)}__${info.size}${ext}`.replace(/[<>:"/\\|?*\x00-\x1f]/g, "_");
}

export class ProjectLibrary {
  /** app: the app object; openVideo(file, {project}); applyProject(p); toast(msg, cls, ttl); onState() */
  constructor({ app, openVideo, applyProject, toast, onState }) {
    Object.assign(this, { app, openVideo, applyProject, toast, onState: onState || (() => {}) });
    this.name = null; this.dirty = false; this.busy = false;
  }

  markDirty() { if (!this.dirty) { this.dirty = true; this.onState(); } }
  setCurrent(name) { this.name = name; this.dirty = false; this.onState(); }

  async list() {
    try {
      const r = await fetch("/api/projects");
      if (!r.ok) return null;
      return await r.json();
    } catch (_) { return null; }
  }

  async save(name = this.name) {
    const { app } = this;
    if (!app.info) { this.toast("open a video first", "warn"); return false; }
    if (!name) return this.dialog({ saveAs: true });
    if (this.busy) return false;
    this.busy = true;
    try {
      const lib = await this.list();
      if (!lib) throw new Error("the local server isn't running (start server\\start.bat). Use \"export .json\" meanwhile.");
      // 1. the source video, once
      const key = mediaKeyOf(app.info);
      const head = await fetch(`/api/media/${enc(key)}`, { method: "HEAD" });
      if (!head.ok) {
        const mb = (app.file.size / 1e6).toFixed(0);
        this.toast(`copying the source video (${mb} MB) into ${lib.root}\\Media, first save only…`, "", 8000);
        await putWithProgress(`/api/media/${enc(key)}`, app.file, (p) => this.onState(`copying video ${Math.round(p * 100)}%`));
        const check = await fetch(`/api/media/${enc(key)}`, { method: "HEAD" });
        if (!check.ok || +check.headers.get("content-length") !== app.file.size) throw new Error("the copied source video doesn't match; try saving again");
      }
      // 2. finished masks the project folder doesn't have yet (mask ids never change once baked)
      const tracks = app.masks.tracks.filter((t) => t.filled === t.frames);
      const ml = await (await fetch(`/api/projects/${enc(name)}/masks`)).json();
      const have = new Set(ml.files || []);
      for (const t of tracks) {
        if (have.has(`${t.id}.json`) && have.has(`${t.id}.bin.gz`)) continue;
        this.onState(`saving mask ${t.name}…`);
        const gz = await gzip(t.data);
        await putWithProgress(`/api/projects/${enc(name)}/masks/${t.id}.bin.gz`, gz);
        await putWithProgress(`/api/projects/${enc(name)}/masks/${t.id}.stats`, t.stats);
        const sizes = (await (await fetch(`/api/projects/${enc(name)}/masks`)).json()).sizes || {};
        if (sizes[`${t.id}.bin.gz`] !== gz.length || sizes[`${t.id}.stats`] !== t.stats.byteLength) {
          throw new Error(`mask "${t.name}" didn't save completely; try saving again`);
        }
        // json last: its presence means the mask is complete
        await putWithProgress(`/api/projects/${enc(name)}/masks/${t.id}.json`, JSON.stringify(t.meta()));
      }
      // 3. the timeline
      const p = { ...JSON.parse(serialise(app.project)), media: key, masks: tracks.map((t) => t.meta()) };
      const r = await fetch(`/api/projects/${enc(name)}`, { method: "PUT", headers: { "content-type": "application/json" }, body: JSON.stringify(p) });
      if (!r.ok) throw new Error(await r.text());
      const res = await r.json();
      this.setCurrent(res.name);
      this.toast(`saved "${res.name}"\n${res.saved}`);
      return true;
    } catch (err) {
      this.toast("save failed: " + err.message, "err", 9000); this.onState();
      return false;
    } finally { this.busy = false; this.onState(); }
  }

  async open(name) {
    const { app } = this;
    if (this.busy) return false;
    this.busy = true;
    try {
      const r = await fetch(`/api/projects/${enc(name)}`);
      if (!r.ok) throw new Error(`no project "${name}"`);
      const p = deserialise(await r.text());
      const sameVideo = app.info && p.media && mediaKeyOf(app.info) === p.media;
      if (sameVideo) this.applyProject(p);
      else {
        if (!p.media) throw new Error("this project has no saved source video");
        this.onState("loading source video…");
        const head = await fetch(`/api/media/${enc(p.media)}`, { method: "HEAD" });
        if (!head.ok) throw new Error(`its source video (${p.media}) is missing from the Media folder`);
        const blob = await fetchBlobChunked(`/api/media/${enc(p.media)}`, { onProgress: (f) => this.onState(`loading source video ${Math.round(f * 100)}%`) });
        // same name/size/lastModified as when it was baked, so masks cached in the browser still match
        const file = new File([blob], p.video?.name || p.media, { type: blob.type || "video/mp4", lastModified: p.video?.lastModified || Date.now() });
        await this.openVideo(file, { project: p });
      }
      // masks the browser no longer has come back from the project folder
      for (const meta of p.masks || []) {
        if (app.masks.get(meta.id)) continue;
        this.onState(`loading mask ${meta.name}…`);
        const base = `/api/projects/${enc(name)}/masks/${meta.id}`;
        let bin, stats;
        try { [bin, stats] = [await fetchBlobChunked(`${base}.bin.gz`), await fetchBlobChunked(`${base}.stats`)]; }
        catch (_) { this.toast(`mask "${meta.name}" is missing; re-bake it from ◐ masks`, "warn"); continue; }
        const t = new MaskTrack(meta);
        let data;
        try { data = await gunzip(bin); } catch (_) { this.toast(`mask "${meta.name}" is damaged; re-bake it from ◐ masks`, "warn"); continue; }
        if (data.length !== t.data.length) { this.toast(`mask "${meta.name}" doesn't fit this video; re-bake it`, "warn"); continue; }
        t.data.set(data);
        t.stats.set(new Float32Array(await stats.arrayBuffer()));
        t.filled = meta.filled ?? meta.frames;
        await app.masks.adopt(t);
      }
      this.setCurrent(name);
      this.toast(`opened "${name}" · ${p.segments.length} effect(s)`);
      return true;
    } catch (err) {
      this.toast("open failed: " + err.message, "err", 9000);
      return false;
    } finally { this.busy = false; this.onState(); }
  }

  async remove(name) {
    const r = await fetch(`/api/projects/${enc(name)}`, { method: "DELETE" });
    if (!r.ok) { this.toast("delete failed: " + (await r.text()), "err"); return false; }
    const res = await r.json();
    if (this.name === name) this.setCurrent(null);
    this.toast(`deleted "${name}"${res.removedMedia ? " (and its source copy, no other project used it)" : ""}`);
    return true;
  }

  // ---------------------------------------------------------------- dialog
  async dialog({ saveAs = false } = {}) {
    document.querySelector(".proj-dialog")?.remove();
    const wrap = document.createElement("div");
    wrap.className = "proj-dialog";
    wrap.innerHTML = `<div class="proj-box" role="dialog" aria-label="projects">
      <div class="proj-head"><span class="proj-title">PROJECTS</span><button class="tl-btn proj-x" title="close">✕</button></div>
      <div class="proj-root meta">checking the local server…</div>
      <div class="proj-save">
        <input type="text" class="proj-name" placeholder="project name" spellcheck="false">
        <button class="tl-btn primary proj-do-save">save</button>
      </div>
      <div class="proj-list"></div>
      <div class="proj-foot">
        <button class="tl-btn proj-export" title="download this timeline as a .sfx.json file">export .json</button>
        <button class="tl-btn proj-import" title="apply a .sfx.json file to the open video">import .json</button>
      </div>
    </div>`;
    document.body.appendChild(wrap);
    const $ = (s) => wrap.querySelector(s);
    const close = () => { wrap.remove(); document.removeEventListener("keydown", onKey); };
    const onKey = (e) => { if (e.key === "Escape") close(); };
    document.addEventListener("keydown", onKey);
    wrap.addEventListener("mousedown", (e) => { if (e.target === wrap) close(); });
    $(".proj-x").onclick = close;
    $(".proj-export").onclick = () => document.querySelector("#btn-export-json")?.click();
    $(".proj-import").onclick = () => { close(); document.querySelector("#project-input").click(); };
    const nameIn = $(".proj-name");
    nameIn.value = this.name || (this.app.info ? this.app.info.name.replace(/\.[^.]+$/, "") : "");
    $(".proj-do-save").disabled = !this.app.info;
    $(".proj-export").disabled = !this.app.info;
    const doSave = async () => {
      const n = nameIn.value.trim();
      if (!n) { nameIn.focus(); return; }
      const existing = (this._items || []).some((it) => it.name.toLowerCase() === n.toLowerCase());
      if (existing && n !== this.name && !confirm(`Replace the saved project "${n}"?`)) return;
      $(".proj-do-save").disabled = true;
      if (await this.save(n)) close(); else $(".proj-do-save").disabled = false;
    };
    $(".proj-do-save").onclick = doSave;
    nameIn.addEventListener("keydown", (e) => { if (e.key === "Enter") doSave(); });
    if (saveAs) setTimeout(() => { nameIn.focus(); nameIn.select(); }, 0);

    const render = async () => {
      const lib = await this.list();
      if (!lib) {
        $(".proj-root").innerHTML = `The project library needs the local server: run <b>server\\start.bat</b> (or the root start.bat), then reopen this.<br>Until then, <b>export .json</b> / <b>import .json</b> still work.`;
        $(".proj-do-save").disabled = true; $(".proj-list").innerHTML = ""; return;
      }
      this._items = lib.projects;
      $(".proj-root").textContent = `saved in ${lib.root}\\Projects`;
      if (!lib.projects.length) { $(".proj-list").innerHTML = `<div class="meta proj-empty">no saved projects yet</div>`; return; }
      $(".proj-list").innerHTML = lib.projects.map((p) => `
        <div class="proj-row${p.name === this.name ? " current" : ""}" data-name="${esc(p.name)}">
          <div class="proj-info">
            <div class="proj-n">${esc(p.name)}${p.name === this.name ? ' <span class="proj-cur">open</span>' : ""}</div>
            <div class="meta">${esc(p.video || "?")} · ${p.segments ?? "?"} fx · ${p.masks ?? 0} mask(s) · ${new Date(p.modified * 1000).toLocaleString()}${p.hasMedia ? "" : ' · <span class="proj-warn">source missing</span>'}</div>
          </div>
          <button class="tl-btn proj-open">open</button>
          <button class="tl-btn danger proj-del" title="delete this project">delete</button>
        </div>`).join("");
      wrap.querySelectorAll(".proj-row").forEach((row) => {
        const n = row.dataset.name;
        row.querySelector(".proj-open").onclick = async () => {
          if (this.dirty && !confirm("You have unsaved changes. Open anyway?")) return;
          close(); await this.open(n);
        };
        row.querySelector(".proj-del").onclick = async () => {
          if (!confirm(`Delete the project "${n}" from your Documents folder? This can't be undone.`)) return;
          if (await this.remove(n)) render();
        };
      });
    };
    render();
    return false;
  }
}
