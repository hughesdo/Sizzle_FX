// Per-segment settings panel. Controls are generated from the effect's
// effect.json uniforms, plus a fixed "segment" block (mix, fades, audio, scope).
// Docked on the right without a dimming backdrop so the preview stays visible
// while you drag sliders.

import { fmt } from "../timeline/timeline.js";

const AUDIO_BANDS = [["level", "overall level"], ["bass", "bass"], ["lowmid", "low-mid"], ["mid", "mid"], ["high", "high"], ["treble", "treble"], ["kick", "kick hits"], ["snare", "snare hits"], ["hat", "hi-hat hits"]];

function el(tag, cls, html) { const e = document.createElement(tag); if (cls) e.className = cls; if (html != null) e.innerHTML = html; return e; }

export class SegmentModal {
  constructor({ root, getEffect, onChange, onRemove, onDuplicate, getMaskTracks, fps }) {
    Object.assign(this, { root, getEffect, onChange, onRemove, onDuplicate, getMaskTracks });
    this.fps = fps || (() => 30);
    this.seg = null;
    root.classList.add("seg-panel", "hidden");
    document.addEventListener("keydown", (e) => { if (e.key === "Escape" && this.seg) this.close(); });
  }

  open(seg) {
    this.seg = seg;
    this.render();
    this.root.classList.remove("hidden");
  }
  close() { this.seg = null; this.root.classList.add("hidden"); }
  isOpenFor(seg) { return this.seg && seg && this.seg.id === seg.id; }

  render() {
    const seg = this.seg; if (!seg) return;
    const fx = this.getEffect(seg.effectId);
    const r = this.root; r.innerHTML = "";
    const head = el("div", "sp-head", `<span>${fx ? fx.name : seg.effectId}</span>`);
    const x = el("button", "modal-x", "✕"); x.onclick = () => this.close(); head.appendChild(x);
    r.appendChild(head);
    r.appendChild(el("div", "sp-sub", `${fmt(seg.start)} → ${fmt(seg.start + seg.dur)} · ${seg.dur.toFixed(2)}s · ${Math.round(seg.dur * this.fps())} frames${fx?.description ? `<br><span class="sp-desc">${fx.description}</span>` : ""}`));
    const body = el("div", "sp-body"); r.appendChild(body);

    if (fx && Object.keys(fx.uniforms).length) {
      body.appendChild(el("div", "sp-section", "effect"));
      for (const [name, u] of Object.entries(fx.uniforms)) body.appendChild(this._control(name, u, seg.params, () => this.onChange(seg, "param")));
    }

    body.appendChild(el("div", "sp-section", "segment"));
    const segVals = seg;
    const fade = (k, label, max) => this._control(k, { type: "float", label, min: 0, max, step: 0.01, default: 0 }, segVals, () => this.onChange(seg, "segment"));
    body.appendChild(this._control("mix", { type: "float", label: "mix", min: 0, max: 1, step: 0.01, default: 1 }, segVals, () => this.onChange(seg, "segment")));
    body.appendChild(fade("fadeIn", "fade in (s)", Math.max(0.01, seg.dur)));
    body.appendChild(fade("fadeOut", "fade out (s)", Math.max(0.01, seg.dur)));
    body.appendChild(this._control("react", { type: "float", label: "audio reactivity", min: 0, max: 3, step: 0.01, default: 1, description: "scales every audio value this effect sees (0 = ignore the music)" }, segVals, () => this.onChange(seg, "segment")));
    body.appendChild(this._control("audioBand", { type: "enum", label: "audio drive", options: AUDIO_BANDS.map((b) => b[1]), values: AUDIO_BANDS.map((b) => b[0]), default: "level", description: "what uAudio follows for effects that use it" }, segVals, () => this.onChange(seg, "segment")));
    const masks = this.getMaskTracks ? this.getMaskTracks() : [];
    const scope = this._control("scope", { type: "enum", label: "scope", options: ["whole frame", "subject only", "background only"], values: ["whole", "subject", "background"], default: "whole",
      description: masks.length ? "apply only inside / outside the subject mask" : "needs a mask: open ◐ masks under the preview and bake one" }, segVals, () => this.onChange(seg, "segment"));
    if (!masks.length) scope.querySelector("select").disabled = true;
    body.appendChild(scope);
    if (masks.length) {
      // which mask track this segment (scope + Body effects) uses; "" = the first one
      const names = ["first mask", ...masks.map((m) => m.name)], ids = ["", ...masks.map((m) => m.id)];
      if (seg.maskTrackId && !ids.includes(seg.maskTrackId)) seg.maskTrackId = null;
      const pick = { maskTrackId: seg.maskTrackId || "" };
      body.appendChild(this._control("maskTrackId", { type: "enum", label: "mask", options: names, values: ids, default: "" }, pick,
        () => { seg.maskTrackId = pick.maskTrackId || null; this.onChange(seg, "segment"); }));
      body.appendChild(this._control("feather", { type: "float", label: "mask feather", min: 0.001, max: 0.5, step: 0.001, default: 0.15 }, segVals, () => this.onChange(seg, "segment")));
      body.appendChild(this._control("choke", { type: "float", label: "mask choke", min: 0.05, max: 0.95, step: 0.01, default: 0.5 }, segVals, () => this.onChange(seg, "segment")));
    }
    body.appendChild(this._control("seed", { type: "int", label: "seed", min: 0, max: 999, step: 1, default: 0 }, segVals, () => this.onChange(seg, "segment")));

    const act = el("div", "sp-actions");
    const btn = (label, cls, fn) => { const b = el("button", "tl-btn " + cls, label); b.onclick = fn; act.appendChild(b); };
    btn("reset", "", () => { seg.params = {}; Object.assign(seg, { mix: 1, fadeIn: 0, fadeOut: 0, react: 1, audioBand: "level", scope: "whole", feather: 0.15, choke: 0.5 }); this.render(); this.onChange(seg, "reset"); });
    btn("duplicate", "", () => { const c = this.onDuplicate(seg); if (c) this.open(c); });
    act.appendChild(el("div", "modal-spacer"));
    btn("remove", "danger", () => { const s = seg; this.close(); this.onRemove(s); });
    btn("done", "primary", () => this.close());
    r.appendChild(act);
  }

  // One labelled control bound to obj[name] (falls back to u.default).
  _control(name, u, obj, changed) {
    const row = el("label", "sp-row");
    row.appendChild(el("span", "sp-label", (u.label || name).replace(/([a-z])([A-Z])/g, "$1 $2").toLowerCase()));
    if (u.description) row.title = u.description;
    const get = () => (obj[name] !== undefined ? obj[name] : u.default);
    const set = (v) => { obj[name] = v; changed(); };
    let input;
    switch (u.type) {
      case "bool": {
        input = el("input"); input.type = "checkbox"; input.checked = !!get();
        input.onchange = () => set(input.checked ? 1 : 0);
        break;
      }
      case "enum": {
        input = el("select");
        (u.options || []).forEach((label, i) => {
          const o = el("option", null, label); o.value = u.values ? u.values[i] : String(i);
          input.appendChild(o);
        });
        input.value = String(get());
        input.onchange = () => set(u.values ? input.value : parseInt(input.value));
        break;
      }
      case "color": {
        input = el("input"); input.type = "color"; input.value = get();
        input.oninput = () => set(input.value);
        break;
      }
      case "text": {
        input = el("input"); input.type = "text"; input.value = get(); input.maxLength = 64;
        input.oninput = () => set(input.value);
        break;
      }
      case "vec2": {
        input = el("span", "sp-vec2");
        const v = [...get()];
        for (let i = 0; i < 2; i++) {
          const s = el("input"); s.type = "range"; s.min = u.min ?? 0; s.max = u.max ?? 1; s.step = u.step ?? 0.01; s.value = v[i];
          s.oninput = () => { v[i] = parseFloat(s.value); set([...v]); };
          input.appendChild(s);
        }
        break;
      }
      default: { // float / int
        input = el("span", "sp-num");
        const s = el("input"); s.type = "range";
        const min = u.min ?? 0, max = u.max ?? 1;
        s.min = min; s.max = max; s.step = u.step ?? (u.type === "int" ? 1 : (max - min) / 200);
        s.value = get();
        const n = el("input"); n.type = "number"; n.step = s.step; n.value = get();
        const apply = (v) => { if (u.type === "int") v = Math.round(v); s.value = v; n.value = v; set(v); };
        s.oninput = () => apply(parseFloat(s.value));
        n.onchange = () => { const v = parseFloat(n.value); if (isFinite(v)) apply(v); };
        s.ondblclick = () => apply(u.default);
        input.appendChild(s); input.appendChild(n);
      }
    }
    row.appendChild(input);
    return row;
  }
}
