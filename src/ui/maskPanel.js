// Masks popover over the preview: bake new mask tracks, watch progress, toggle
// the check overlay, delete. SAM 2 mode turns preview clicks into prompt points.

import { PROVIDERS } from "../mask/masks.js";
import { MaskTrack } from "../mask/maskTrack.js";

const el = (tag, cls, html) => { const e = document.createElement(tag); if (cls) e.className = cls; if (html != null) e.innerHTML = html; return e; };

export class MaskPanel {
  /**
   * opts: { root, button, canvas, manager, getFrameIndex, onOverlay(id|null), onSelectPreview(track|null), toast }
   */
  constructor(opts) {
    Object.assign(this, opts);
    this.status = new Map();
    this.overlay = null;
    this.select = null; // {frameIndex, points:[{x,y,label}], busy, preview: MaskTrack}
    this.root.classList.add("mask-panel", "hidden");
    this.button.addEventListener("click", () => this.toggle());
    this.dots = el("div", "sel-dots"); this.canvas.parentNode.appendChild(this.dots);
    this.canvas.addEventListener("click", (e) => this._click(e, 1));
    this.canvas.addEventListener("contextmenu", (e) => { if (this.select) { e.preventDefault(); this._click(e, 0); } });
    this.render();
  }

  toggle(force) {
    const show = force ?? this.root.classList.contains("hidden");
    this.root.classList.toggle("hidden", !show);
    this.button.classList.toggle("on", show);
    if (!show && this.select) this.endSelect();
  }

  setStatus(track, msg) { this.status.set(track.id, msg); const s = this.root.querySelector(`[data-status="${track.id}"]`); if (s) s.textContent = msg; }

  render() {
    const m = this.manager, r = this.root;
    r.innerHTML = "";
    const head = el("div", "mp-head", "<span>masks</span>");
    const x = el("button", "modal-x", "✕"); x.onclick = () => this.toggle(false); head.appendChild(x);
    r.appendChild(head);
    if (!m.info) { r.appendChild(el("div", "mp-empty", "open a video first")); return; }

    const list = el("div", "mp-list");
    if (!m.tracks.length) list.appendChild(el("div", "mp-empty", "no masks yet. A mask lets any effect hit only the subject (or only the background), and powers the Body effects."));
    for (const t of m.tracks) {
      const baking = m.job?.track === t;
      const row = el("div", "mp-row" + (baking ? " baking" : ""));
      const name = el("input", "mp-name"); name.value = t.name; name.title = "rename";
      name.onchange = () => m.rename(t.id, name.value.trim() || t.name);
      const pct = Math.round((t.filled / t.frames) * 100);
      const meta = el("div", "mp-meta", `<span>${PROVIDERS[t.provider]?.label || t.provider} · ${t.width}×${t.height}</span><span data-status="${t.id}">${baking ? (this.status.get(t.id) || "starting…") : pct === 100 ? `${t.frames} frames` : `${pct}%`}</span>`);
      const bar = el("div", "mp-bar"); bar.appendChild(el("div", "mp-fill")).style.width = pct + "%";
      const eye = el("button", "tl-btn mp-eye" + (this.overlay === t.id ? " on" : ""), "view");
      eye.title = "show this mask over the preview";
      eye.onclick = () => { this.overlay = this.overlay === t.id ? null : t.id; this.onOverlay(this.overlay); this.render(); };
      const del = el("button", "tl-btn danger", baking ? "stop" : "✕");
      del.title = baking ? "cancel this bake" : "delete this mask";
      del.onclick = () => { if (baking) m.cancel(); else if (confirm(`Delete mask "${t.name}"?`)) { if (this.overlay === t.id) { this.overlay = null; this.onOverlay(null); } m.remove(t.id); } };
      const top = el("div", "mp-top"); top.append(name, eye, del);
      row.append(top, meta, bar);
      list.appendChild(row);
    }
    r.appendChild(list);

    if (this.select) {
      const s = this.select;
      const box = el("div", "mp-select");
      box.appendChild(el("div", "mp-hint", `click the subject on the preview · <b>right-click</b> to exclude · frame ${s.frameIndex} · ${s.points.length} point${s.points.length === 1 ? "" : "s"}${s.busy ? " · thinking…" : s.score != null ? ` · confidence ${(s.score * 100).toFixed(0)}%` : ""}`));
      const lv = el("div", "mp-actions mp-levels");
      ["whole", "part", "detail"].forEach((label, k) => {
        const b = el("button", "tl-btn" + (s.level === k ? " on" : ""), label);
        b.title = "SAM gives three readings of a click; pick how much of the object to take";
        b.onclick = () => { s.level = k; if (s.points.length) this._run(); else this.render(); };
        lv.appendChild(b);
      });
      box.appendChild(lv);
      const row = el("div", "mp-actions");
      const go = el("button", "tl-btn primary", "track it"); go.disabled = !s.points.length || s.busy || m.busy;
      go.onclick = () => this._bake("sam2", { prompt: { frameIndex: s.frameIndex, points: s.points, level: s.level } });
      const clr = el("button", "tl-btn", "clear"); clr.onclick = () => { s.points = []; s.score = null; this.onSelectPreview(null); this._dots(); this.render(); };
      const cancel = el("button", "tl-btn", "cancel"); cancel.onclick = () => this.endSelect();
      row.append(go, clr, cancel);
      box.appendChild(row);
      r.appendChild(box);
    } else {
      const add = el("div", "mp-actions");
      const b = (prov, label, fn) => { const x = el("button", "tl-btn", label); x.disabled = m.busy; x.title = PROVIDERS[prov].label; x.onclick = fn; add.appendChild(x); };
      b("rvm", "+ auto person", () => this._bake("rvm", { params: { downsample: 0.5 } }));
      b("key", "+ green screen", () => this._bake("key", { params: { tolerance: 0.12, softness: 0.1 } }));
      b("sam2", "+ click to select", () => this.beginSelect());
      r.appendChild(add);
      r.appendChild(el("div", "mp-foot", "masks bake once per video and are saved in this browser. AI models run on your GPU (WebGPU)."));
    }
  }

  async _bake(provider, opts) {
    const m = this.manager;
    if (this.select) this.endSelect(true);
    try {
      const p = m.bake(provider, opts);
      this.render();
      const t = await p;
      this.toast(`mask "${t.name}" ready (${t.frames} frames)`);
      if (!this.overlay) { this.overlay = t.id; this.onOverlay(t.id); }
    } catch (err) {
      if (!/cancel/i.test(err.message)) this.toast("mask bake failed: " + err.message, "err", 9000);
    }
    this.render();
  }

  // ---------------------------------------------------------------- SAM 2 selection
  beginSelect() {
    this.select = { frameIndex: this.getFrameIndex(), points: [], busy: false, score: null, level: 0 };
    this.canvas.classList.add("selecting");
    this.render();
  }
  endSelect(keepPreview = false) {
    this.select = null;
    this.canvas.classList.remove("selecting");
    this._dots();
    if (!keepPreview) this.onSelectPreview(null);
    else this.onSelectPreview(null);
    this.render();
  }
  async _click(e, label) {
    const s = this.select; if (!s) return;
    e.preventDefault();
    const r = this.canvas.getBoundingClientRect();
    const x = (e.clientX - r.left) / r.width, y = (e.clientY - r.top) / r.height;
    if (x < 0 || x > 1 || y < 0 || y > 1) return;
    const fi = this.getFrameIndex();
    if (fi !== s.frameIndex) { s.frameIndex = fi; s.points = []; }
    s.points.push({ x, y, label });
    this._dots();
    await this._run();
  }
  async _run() {
    const s = this.select; if (!s) return;
    s.busy = true; this.render();
    try {
      const res = await this.manager.select(s.frameIndex, s.points, s.level);
      if (this.select !== s) return;
      const t = new MaskTrack({ id: "__select", name: "selection", provider: "sam2", width: res.width, height: res.height, frames: 1 });
      t.setFrame(0, res.alpha);
      s.score = res.score;
      this.onSelectPreview(t);
    } catch (err) { this.toast("SAM 2 failed: " + err.message, "err", 9000); }
    s.busy = false; this.render();
  }
  _dots() {
    this.dots.innerHTML = "";
    if (!this.select) return;
    const cr = this.canvas.getBoundingClientRect(), pr = this.dots.parentNode.getBoundingClientRect();
    for (const p of this.select.points) {
      const d = el("div", "sel-dot" + (p.label ? "" : " neg"));
      d.style.left = cr.left - pr.left + p.x * cr.width + "px";
      d.style.top = cr.top - pr.top + p.y * cr.height + "px";
      this.dots.appendChild(d);
    }
  }
}
