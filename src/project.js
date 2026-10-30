// Project state (lanes + segments) and the per-frame layer list that BOTH preview
// and export feed to Renderer.render(). Saved as JSON (autosave + file export).

import { sampleAnalysis, fftRowAt } from "./audio/analysis.js";

export const PROJECT_VERSION = 1;
let _idc = 0;
export const uid = (p = "s") => `${p}${Date.now().toString(36)}${(++_idc).toString(36)}`;

export function newProject(video) {
  return {
    version: PROJECT_VERSION,
    video: video ? { name: video.name, size: video.size, lastModified: video.lastModified, duration: video.duration, fps: video.fps, width: video.width, height: video.height } : null,
    lanes: [{ id: "L1", name: "FX 1" }, { id: "L2", name: "FX 2" }, { id: "L3", name: "FX 3" }],
    segments: [],
    output: { scale: 1 },
  };
}

export function newSegment(effect, lane, start, dur) {
  return {
    id: uid("s"), lane, effectId: effect.id, start, dur,
    params: {}, mix: 1, fadeIn: 0, fadeOut: 0,
    react: 1, audioBand: "level", scope: "whole", maskTrackId: null, // null = first mask track
    feather: 0.15, choke: 0.5, seed: Math.floor(Math.random() * 1000),
  };
}

// Fade-shaped amount for a segment at time t (0 outside it).
export function segAmount(seg, t) {
  if (t < seg.start || t >= seg.start + seg.dur) return 0;
  const lt = t - seg.start;
  let a = seg.mix ?? 1;
  if (seg.fadeIn > 0) a *= Math.min(1, lt / seg.fadeIn);
  if (seg.fadeOut > 0) a *= Math.min(1, (seg.dur - lt) / seg.fadeOut);
  return Math.max(0, a);
}

/**
 * Everything Renderer.render needs for one frame, except the uploaded source.
 * effects: Map id -> effect, entries: id -> compiled entry (renderer.programs)
 */
export function buildFrame(project, { time, index, dt, analysis, effects, entries, maskTracks = [], overlayMask = null }) {
  const layers = [];
  project.lanes.forEach((lane, li) => {
    for (const seg of project.segments) {
      if (seg.lane !== lane.id) continue;
      const amount = segAmount(seg, time);
      if (amount <= 0) continue;
      const effect = effects.get(seg.effectId);
      if (!effect) continue;
      const fps = project.video?.fps || 30;
      const lt = time - seg.start;
      layers.push({
        seg, effect, entry: entries.get(effect.id), lane: li,
        local: { t: Math.min(1, lt / seg.dur), time: lt, frame: Math.max(0, Math.round(lt * fps)), amount },
      });
    }
  });
  // mask tracks for this frame (first = default for segments without a pick + history alpha)
  const masks = [];
  for (const t of maskTracks) {
    if (!t.filled) continue;
    const i = Math.max(0, Math.min(t.frames - 1, index));
    masks.push({ id: t.id, data: t.frame(i), w: t.width, h: t.height, index: i, version: t.filled < t.frames ? t.filled : 0, stats: t.statsAt(i) });
  }
  return {
    index, time, dt, layers, masks, overlayMask: masks.some((m) => m.id === overlayMask) ? overlayMask : null,
    sampleRate: analysis?.sampleRate || 48000,
    audio: sampleAnalysis(analysis, time),
    fftBytes: fftRowAt(analysis, time),
  };
}

// --- persistence -------------------------------------------------------------
export function fileKey(v) { return v ? `sizzlefx:${v.name}:${v.size}` : "sizzlefx:none"; }

export function autosave(project) {
  try { localStorage.setItem(fileKey(project.video), JSON.stringify(project)); } catch (_) {}
}
export function loadAutosave(video) {
  try { const s = localStorage.getItem(fileKey(video)); return s ? JSON.parse(s) : null; } catch (_) { return null; }
}
export function serialise(project) { return JSON.stringify(project, null, 1); }
export function deserialise(text) {
  const p = JSON.parse(text);
  if (!p || !Array.isArray(p.segments) || !Array.isArray(p.lanes)) throw new Error("not a Sizzle FX project file");
  return p;
}
