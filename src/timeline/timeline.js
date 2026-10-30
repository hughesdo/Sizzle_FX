// Multi-lane effect timeline. Ported from Sizzle static/app.js (zoom, ruler,
// waveform, beat ticks, snap/magnet, neighbour collision, drag/resize, playhead)
// and extended with lanes: drag a segment up/down to change lane, drag either
// edge to resize. Bottom lane renders first; each lane above feeds on it.

import { newSegment } from "../project.js";

const MIN_SEG = 0.2;
const DEFAULT_SEG = 4.0;
const SNAP_PX = 8;
const MAGNET_PX = 22;
const LANE_H = 52;

const clamp = (v, lo, hi) => Math.max(lo, Math.min(hi, v));
export function fmt(t) { if (!isFinite(t)) t = 0; const m = Math.floor(t / 60), s = t % 60; return `${m}:${s.toFixed(1).padStart(4, "0")}`; }

const CAT_COLORS = {
  Body: "#ff5d3b", Glitch: "#ff3b8d", Color: "#ffb03a", Look: "#ffd23a", Blur: "#7aa2ff",
  Distort: "#b07aff", Temporal: "#3bffd0", Light: "#fff07a", Stylize: "#7affa2", Overlay: "#5ad1ff",
  Scene: "#9b8cff", Keying: "#3bff6a", Feedback: "#3bd0ff", Misc: "#9aa0ad",
};
export const catColor = (c) => CAT_COLORS[c] || CAT_COLORS.Misc;

export class Timeline {
  /**
   * opts: { root, getProject, getEffect, onChange, onSelect, onOpen, onSeek, getTime }
   */
  constructor(opts) {
    Object.assign(this, opts);
    this.zoom = 1; this.baseFit = 100;
    this.selectedId = null;
    this.analysis = null; this.duration = 0;
    this._build();
  }

  // ---------------------------------------------------------------- DOM
  _build() {
    const r = this.root;
    r.innerHTML = `
      <div class="tl-toolbar">
        <button class="tl-play" data-k="play" title="play / pause (space)"><span class="ph-icon">▶</span></button>
        <span class="tl-time" data-k="time">0:00.0 / 0:00.0</span>
        <span class="tl-zoomlabel">zoom</span>
        <input type="range" data-k="zoom" min="1" max="40" step="0.05" value="1">
        <button class="tl-btn" data-k="fit">fit</button>
        <button class="tl-btn" data-k="addlane" title="add an effect lane">+ lane</button>
        <span class="tl-meta" data-k="meta"></span>
      </div>
      <div class="tl-body">
        <div class="tl-heads" data-k="heads"></div>
        <div class="timeline-scroll" data-k="scroll">
          <div class="timeline-inner" data-k="inner">
            <div class="tl-ruler" data-k="ruler"></div>
            <div class="tl-thumbs" data-k="thumbs"></div>
            <canvas class="tl-wave" data-k="wave" height="44"></canvas>
            <div class="tl-ticks" data-k="ticks"></div>
            <div class="tl-lanes" data-k="lanes"></div>
            <div class="tl-playhead" data-k="playhead"><div class="tl-playhead-grip" data-k="grip" title="drag to move the play position"></div></div>
          </div>
        </div>
      </div>
      <div class="tl-help" data-k="help">drag an effect from the library onto a lane · drag edges to resize · drag up/down to change lane · click to edit</div>`;
    this.el = {};
    r.querySelectorAll("[data-k]").forEach((e) => (this.el[e.dataset.k] = e));
    const { zoom, fit, scroll, ruler, wave, grip, addlane, thumbs } = this.el;
    zoom.addEventListener("input", () => { this._zoomAround(parseFloat(zoom.value)); });
    fit.addEventListener("click", () => { this.fitZoom(); this.layout(); });
    addlane.addEventListener("click", () => this.addLane());
    const seek = (ev) => { const t = this._timeAt(ev); this.onSeek(t); };
    ruler.addEventListener("click", seek);
    wave.addEventListener("click", seek);
    thumbs.addEventListener("click", seek);
    this._wirePlayheadDrag(grip);
    this._wireDrop(scroll);
    window.addEventListener("resize", () => this.layout());
    scroll.addEventListener("wheel", (ev) => {
      if (!ev.ctrlKey) return;
      ev.preventDefault();
      this._zoomAround(this.zoom * (ev.deltaY < 0 ? 1.15 : 1 / 1.15), ev);
    }, { passive: false });
  }

  get pps() { return this.baseFit * this.zoom; }
  xOf(t) { return t * this.pps; }
  tOf(x) { return x / this.pps; }
  _timeAt(ev) { const rect = this.el.inner.getBoundingClientRect(); return clamp(this.tOf(ev.clientX - rect.left), 0, this.duration); }

  setMedia({ duration, analysis }) {
    this.duration = duration; this.analysis = analysis;
    this.fitZoom(); this.render();
  }
  setAnalysis(a) { this.analysis = a; this.layout(); }

  fitZoom() {
    const w = this.el.scroll.clientWidth || 1100;
    this.baseFit = this.duration ? (w - 2) / this.duration : 100;
    this.zoom = 1; this.el.zoom.value = "1";
  }
  _zoomAround(z, ev) {
    const sc = this.el.scroll;
    const anchorX = ev ? ev.clientX - sc.getBoundingClientRect().left : sc.clientWidth / 2;
    const tAnchor = this.tOf(sc.scrollLeft + anchorX);
    this.zoom = clamp(z, 1, 40); this.el.zoom.value = String(this.zoom);
    this.layout();
    sc.scrollLeft = Math.max(0, this.xOf(tAnchor) - anchorX);
  }

  addLane() {
    const p = this.getProject();
    const n = p.lanes.length + 1;
    p.lanes.push({ id: `L${Date.now().toString(36)}`, name: `FX ${n}` });
    this.render(); this.onChange("lanes");
  }

  // top row on screen = highest lane (renders last, on top)
  _lanesTopDown() { return [...this.getProject().lanes].reverse(); }

  render() {
    const { lanes, heads } = this.el;
    lanes.innerHTML = ""; heads.innerHTML = "";
    const hdTop = document.createElement("div"); hdTop.className = "tl-head-spacer"; heads.appendChild(hdTop);
    for (const lane of this._lanesTopDown()) {
      const row = document.createElement("div");
      row.className = "tl-lane"; row.dataset.lane = lane.id; row.style.height = LANE_H + "px";
      lanes.appendChild(row);
      const hd = document.createElement("div");
      hd.className = "tl-head"; hd.style.height = LANE_H + "px";
      hd.innerHTML = `<span>${lane.name}</span>`;
      const p = this.getProject();
      if (p.lanes.length > 1 && !p.segments.some((s) => s.lane === lane.id)) {
        const x = document.createElement("button"); x.className = "tl-head-x"; x.textContent = "✕"; x.title = "remove empty lane";
        x.onclick = () => { p.lanes = p.lanes.filter((l) => l.id !== lane.id); this.render(); this.onChange("lanes"); };
        hd.appendChild(x);
      }
      heads.appendChild(hd);
    }
    for (const seg of this.getProject().segments) this._laneEl(seg.lane)?.appendChild(this._segEl(seg));
    this.layout();
  }

  _laneEl(id) { return this.el.lanes.querySelector(`.tl-lane[data-lane="${id}"]`); }

  layout() {
    if (!this.duration) return;
    const { scroll, inner, wave, ruler, ticks } = this.el;
    const innerW = Math.max(scroll.clientWidth, this.xOf(this.duration));
    inner.style.width = innerW + "px";
    // waveform
    wave.width = innerW; const h = wave.height;
    const ctx = wave.getContext("2d");
    ctx.clearRect(0, 0, innerW, h);
    const peaks = this.analysis?.peaks;
    if (peaks?.length) {
      ctx.strokeStyle = "#3bffd0"; ctx.globalAlpha = 0.7; ctx.beginPath();
      const n = peaks.length, step = Math.max(1, Math.floor(n / innerW));
      for (let i = 0; i < n; i += step) {
        const x = (i / n) * innerW, amp = peaks[i] * (h * 0.46);
        ctx.moveTo(x, h / 2 - amp); ctx.lineTo(x, h / 2 + amp);
      }
      ctx.stroke(); ctx.globalAlpha = 1;
    }
    // ruler
    ruler.innerHTML = "";
    const steps = [0.25, 0.5, 1, 2, 5, 10, 15, 30, 60, 120];
    const step = steps.find((s) => s >= 80 / this.pps) || 300;
    for (let t = 0; t <= this.duration + 1e-6; t += step) {
      const l = document.createElement("div"); l.className = "rlabel";
      l.style.left = this.xOf(t) + "px"; l.textContent = fmt(t); ruler.appendChild(l);
    }
    // beat ticks
    ticks.innerHTML = "";
    const beats = this.analysis?.beats || [], downs = new Set((this.analysis?.downbeats || []).map((t) => t.toFixed(3)));
    const beatPx = beats.length > 1 ? this.xOf(beats[1] - beats[0]) : 999;
    for (const t of beats) {
      const down = downs.has(t.toFixed(3));
      if (!down && beatPx < 5) continue;
      const d = document.createElement("div"); d.className = "tick" + (down ? " down" : "");
      d.style.left = this.xOf(t) + "px"; ticks.appendChild(d);
    }
    for (const seg of this.getProject().segments) this._place(seg);
    this.movePlayhead(this.getTime(), false);
    this._meta();
  }

  _meta() {
    const n = this.getProject().segments.length;
    this.el.meta.textContent = n ? `${n} effect${n > 1 ? "s" : ""} on timeline` : "drag an effect from the library onto a lane";
  }

  // ---------------------------------------------------------------- thumbnails
  clearThumbs() { this.el.thumbs.innerHTML = ""; }
  addThumb(time, canvas) {
    const w = canvas.width;
    const d = document.createElement("div"); d.className = "tl-thumb";
    d.style.left = `${(time / this.duration) * 100}%`;
    d.style.width = `${w}px`;
    canvas.className = "tl-thumb-img";
    d.appendChild(canvas);
    this.el.thumbs.appendChild(d);
  }

  // ---------------------------------------------------------------- segments
  _segEl(seg) {
    const fx = this.getEffect(seg.effectId);
    const el = document.createElement("div");
    el.className = "seg"; el.dataset.id = seg.id;
    el.style.setProperty("--c", catColor(fx?.category));
    el.innerHTML = `<div class="seg-l" title="drag to trim start"></div>
      <div class="seg-name">${fx ? fx.name : `missing: ${seg.effectId}`}</div>
      <div class="seg-sub"><span class="seg-time"></span><span class="seg-dur"></span></div>
      <div class="seg-fade"></div>
      <div class="seg-r" title="drag to resize"></div>`;
    if (!fx) el.classList.add("missing");
    if (seg.id === this.selectedId) el.classList.add("selected");
    seg._el = el;
    el.addEventListener("pointerdown", (e) => this._onPointerDown(e, seg));
    el.addEventListener("click", () => { if (el._moved) { el._moved = false; return; } this.onOpen(seg); });
    return el;
  }

  _place(seg) {
    const el = seg._el; if (!el) return;
    el.style.left = this.xOf(seg.start) + "px";
    el.style.width = Math.max(6, this.xOf(seg.dur)) + "px";
    el.querySelector(".seg-time").textContent = fmt(seg.start);
    el.querySelector(".seg-dur").textContent = seg.dur.toFixed(2) + "s";
    const fade = el.querySelector(".seg-fade");
    const fi = seg.dur ? (seg.fadeIn || 0) / seg.dur * 100 : 0, fo = seg.dur ? (seg.fadeOut || 0) / seg.dur * 100 : 0;
    fade.style.background = `linear-gradient(90deg, rgba(0,0,0,.55) 0%, transparent ${fi}%, transparent ${100 - fo}%, rgba(0,0,0,.55) 100%)`;
    el.classList.toggle("scoped", seg.scope && seg.scope !== "whole");
  }

  refreshSeg(seg) {
    const fx = this.getEffect(seg.effectId);
    if (seg._el) { seg._el.querySelector(".seg-name").textContent = fx ? fx.name : seg.effectId; this._place(seg); }
  }

  select(seg) {
    this.selectedId = seg ? seg.id : null;
    this.el.lanes.querySelectorAll(".seg").forEach((e) => e.classList.toggle("selected", e.dataset.id === this.selectedId));
    this.onSelect && this.onSelect(seg);
  }

  // ---------------------------------------------------------------- snapping
  _snapPoints(exceptId) {
    const pts = [0, this.duration, ...(this.analysis?.beats || [])];
    for (const s of this.getProject().segments) if (s.id !== exceptId) pts.push(s.start, s.start + s.dur);
    pts.push(this.getTime());
    return pts;
  }
  _snap(t, exceptId) {
    const tol = SNAP_PX / this.pps;
    let best = t, bd = tol;
    for (const p of this._snapPoints(exceptId)) { const d = Math.abs(p - t); if (d < bd) { bd = d; best = p; } }
    return best;
  }
  _magnet(t, exceptId, laneId) {
    const tol = MAGNET_PX / this.pps;
    const pts = [0, this.duration, this.getTime()];
    for (const s of this.getProject().segments) if (s.id !== exceptId && s.lane === laneId) pts.push(s.start, s.start + s.dur);
    let best = null, bd = tol;
    for (const p of pts) { const d = Math.abs(p - t); if (d < bd) { bd = d; best = p; } }
    return best != null ? best : this._snap(t, exceptId);
  }
  // free span around time t in a lane (ignoring one segment)
  _room(laneId, t, exceptId) {
    let left = 0, right = this.duration;
    for (const o of this.getProject().segments) {
      if (o.id === exceptId || o.lane !== laneId) continue;
      if (t > o.start - 1e-6 && t < o.start + o.dur - 1e-6) return null; // inside another
      if (o.start + o.dur <= t + 1e-6) left = Math.max(left, o.start + o.dur);
      if (o.start >= t - 1e-6) right = Math.min(right, o.start);
    }
    return { left, right };
  }
  _bounds(seg, laneId = seg.lane) {
    let left = 0, right = this.duration;
    for (const o of this.getProject().segments) {
      if (o.id === seg.id || o.lane !== laneId) continue;
      if (o.start + o.dur <= seg.start + 1e-6) left = Math.max(left, o.start + o.dur);
      else if (o.start >= seg.start + seg.dur - 1e-6) right = Math.min(right, o.start);
      else return null; // overlaps
    }
    return { left, right };
  }
  _laneAtY(clientY) {
    const rows = [...this.el.lanes.querySelectorAll(".tl-lane")];
    for (const r of rows) { const b = r.getBoundingClientRect(); if (clientY >= b.top && clientY < b.bottom) return r.dataset.lane; }
    return null;
  }

  // ---------------------------------------------------------------- drag/resize
  _onPointerDown(e, seg) {
    if (e.button !== 0) return;
    e.preventDefault();
    const mode = e.target.classList.contains("seg-r") ? "right" : e.target.classList.contains("seg-l") ? "left" : "move";
    const el = seg._el; el._moved = false;
    const startX = e.clientX, o = { start: seg.start, dur: seg.dur, lane: seg.lane };
    el.setPointerCapture(e.pointerId);
    el.classList.add("dragging");
    this.select(seg);
    const move = (ev) => {
      const dx = ev.clientX - startX;
      if (Math.abs(dx) > 3 || Math.abs(ev.clientY - e.clientY) > 6) el._moved = true;
      if (mode === "right") {
        const b = this._bounds({ ...seg, start: o.start, dur: o.dur }) || { left: 0, right: this.duration };
        let end = this._magnet(o.start + o.dur + this.tOf(dx), seg.id, seg.lane);
        seg.dur = clamp(end - o.start, MIN_SEG, b.right - o.start);
      } else if (mode === "left") {
        const b = this._bounds({ ...seg, start: o.start, dur: o.dur }) || { left: 0, right: this.duration };
        const end = o.start + o.dur;
        let st = this._magnet(o.start + this.tOf(dx), seg.id, seg.lane);
        st = clamp(st, b.left, end - MIN_SEG);
        seg.start = st; seg.dur = end - st;
      } else {
        // lane change follows the pointer if the target lane has room
        const laneId = this._laneAtY(ev.clientY) || seg.lane;
        let ns = o.start + this.tOf(dx);
        const sL = this._magnet(ns, seg.id, laneId), sR = this._magnet(ns + seg.dur, seg.id, laneId) - seg.dur;
        ns = Math.abs(sL - ns) <= Math.abs(sR - ns) ? sL : sR;
        ns = clamp(ns, 0, this.duration - seg.dur);
        const trial = { ...seg, start: ns, lane: laneId };
        let b = this._bounds(trial, laneId);
        if (b) {
          trial.start = clamp(ns, b.left, b.right - seg.dur);
          if (b.right - b.left >= seg.dur - 1e-6) {
            if (laneId !== seg.lane) { seg.lane = laneId; this._laneEl(laneId).appendChild(el); }
            seg.start = trial.start;
          }
        } else if (laneId === seg.lane) {
          // pushing into a neighbour in the same lane: clamp against the original bounds
          const bo = this._bounds({ ...seg, start: o.start, lane: o.lane }, o.lane);
          if (bo) seg.start = clamp(ns, bo.left, bo.right - seg.dur);
        }
      }
      this._place(seg);
    };
    const up = () => {
      el.releasePointerCapture(e.pointerId);
      el.classList.remove("dragging");
      window.removeEventListener("pointermove", move);
      window.removeEventListener("pointerup", up);
      if (el._moved) this.onChange("segment", seg);
    };
    window.addEventListener("pointermove", move);
    window.addEventListener("pointerup", up);
  }

  // ---------------------------------------------------------------- drop from library
  _wireDrop(scroll) {
    let ghost = null;
    const target = (ev) => {
      const laneId = this._laneAtY(ev.clientY);
      if (!laneId) return null;
      let t = this._magnet(this._timeAt(ev), null, laneId);
      const room = this._room(laneId, t, null);
      if (!room) return { laneId, ok: false };
      const dur = Math.min(DEFAULT_SEG, room.right - t);
      return { laneId, start: t, dur, ok: dur >= MIN_SEG };
    };
    scroll.addEventListener("dragover", (ev) => {
      if (!ev.dataTransfer.types.includes("text/x-effect")) return;
      ev.preventDefault();
      const tg = target(ev);
      if (!ghost) { ghost = document.createElement("div"); ghost.className = "drop-ghost"; }
      if (!tg) { ghost.remove(); return; }
      const lane = this._laneEl(tg.laneId);
      if (ghost.parentNode !== lane) lane.appendChild(ghost);
      ghost.classList.toggle("bad", !tg.ok);
      ghost.style.left = this.xOf(tg.start ?? this._timeAt(ev)) + "px";
      ghost.style.width = this.xOf(tg.ok ? tg.dur : 0.5) + "px";
    });
    scroll.addEventListener("dragleave", (ev) => { if (ev.target === scroll && ghost) { ghost.remove(); ghost = null; } });
    scroll.addEventListener("drop", (ev) => {
      const id = ev.dataTransfer.getData("text/x-effect");
      if (ghost) { ghost.remove(); ghost = null; }
      if (!id) return;
      ev.preventDefault();
      const tg = target(ev);
      if (!tg || !tg.ok) { this.flash("no room there, try a gap or another lane"); return; }
      this.addSegment(id, tg.laneId, tg.start, tg.dur);
    });
  }

  addSegment(effectId, laneId, start, dur) {
    const fx = this.getEffect(effectId); if (!fx) return null;
    const seg = newSegment(fx, laneId, start, dur);
    this.getProject().segments.push(seg);
    this._laneEl(laneId).appendChild(this._segEl(seg));
    this._place(seg); this.select(seg); this._meta();
    this.onChange("add", seg);
    return seg;
  }

  // place at playhead in the first lane that has room
  addAtPlayhead(effectId) {
    const t = this.getTime();
    for (const lane of this.getProject().lanes) {
      const room = this._room(lane.id, t, null);
      if (room && room.right - t >= MIN_SEG) return this.addSegment(effectId, lane.id, t, Math.min(DEFAULT_SEG, room.right - t));
    }
    this.addLane();
    const lane = this.getProject().lanes.at(-1);
    return this.addSegment(effectId, lane.id, t, Math.min(DEFAULT_SEG, this.duration - t));
  }

  removeSegment(seg) {
    const p = this.getProject();
    p.segments = p.segments.filter((s) => s.id !== seg.id);
    seg._el?.remove();
    if (this.selectedId === seg.id) this.select(null);
    this._meta();
    this.onChange("remove", seg);
  }

  duplicateSegment(seg) {
    const p = this.getProject();
    const t = seg.start + seg.dur;
    const lanes = [seg.lane, ...p.lanes.map((l) => l.id).filter((l) => l !== seg.lane)];
    for (const laneId of lanes) {
      const room = this._room(laneId, t, null);
      if (room && room.right - t >= MIN_SEG) {
        const copy = this.addSegment(seg.effectId, laneId, t, Math.min(seg.dur, room.right - t));
        Object.assign(copy, JSON.parse(JSON.stringify({ ...seg, _el: undefined, id: copy.id, lane: laneId, start: t, dur: copy.dur })));
        copy._el = this.el.lanes.querySelector(`.seg[data-id="${copy.id}"]`);
        this._place(copy); this.onChange("segment", copy);
        return copy;
      }
    }
    this.flash("no room after this segment");
    return null;
  }

  // ---------------------------------------------------------------- playhead
  movePlayhead(t, follow = true) {
    const { playhead, scroll, inner, time } = this.el;
    if (!this.duration) return;
    playhead.style.display = "block";
    const px = this.xOf(t);
    playhead.style.left = px + "px";
    if (follow) {
      const left = scroll.scrollLeft, vw = scroll.clientWidth;
      if (px > left + vw - 60 || px < left + 30) scroll.scrollLeft = clamp(px - vw * 0.4, 0, inner.clientWidth - vw);
    }
    time.innerHTML = `<span class="cur">${fmt(t)}</span> / ${fmt(this.duration)}`;
    for (const s of this.getProject().segments) s._el?.classList.toggle("playing", t >= s.start && t < s.start + s.dur);
  }
  setPlaying(on) {
    const b = this.el.play;
    b.querySelector(".ph-icon").textContent = on ? "⏸" : "▶";
    b.classList.toggle("playing", on);
  }
  _wirePlayheadDrag(grip) {
    let drag = false;
    grip.addEventListener("pointerdown", (ev) => { ev.preventDefault(); ev.stopPropagation(); drag = true; grip.setPointerCapture(ev.pointerId); this.onScrubStart?.(); });
    grip.addEventListener("pointermove", (ev) => { if (drag) this.onSeek(this._timeAt(ev)); });
    const end = (ev) => { if (!drag) return; drag = false; try { grip.releasePointerCapture(ev.pointerId); } catch (_) {} this.onScrubEnd?.(); };
    grip.addEventListener("pointerup", end); grip.addEventListener("pointercancel", end);
  }

  flash(msg) {
    const h = this.el.help; h.textContent = msg; h.classList.add("flash");
    clearTimeout(this._ft);
    this._ft = setTimeout(() => { h.classList.remove("flash"); h.textContent = "drag an effect from the library onto a lane · drag edges to resize · drag up/down to change lane · click to edit"; }, 4000);
  }
}
