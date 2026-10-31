// Sizzle FX — wiring: registry, library, preview, timeline, segment panel, export.
import { Renderer } from "./render/renderer.js";
import { Timeline } from "./timeline/timeline.js";
import { Library } from "./ui/library.js";
import { SegmentModal } from "./ui/segmentModal.js";
import { detectCapabilities, chooseDefaultMode } from "./ui/renderMode.js";
import { probeVideo, decodeMonoAudio, thumbnails, frameCanvasAt } from "./media/source.js";
import { ThumbMaker, THUMB_W, THUMB_H } from "./ui/thumbs.js";
import { exportVideo, PRESETS } from "./media/export.js";
import { serverExport } from "./media/serverRender.js";
import { newProject, buildFrame, autosave, loadAutosave, serialise, deserialise } from "./project.js";
import { MaskManager } from "./mask/masks.js";
import { MaskPanel } from "./ui/maskPanel.js";
import { ProjectLibrary } from "./ui/projects.js";
import { BASE, HOSTED } from "./base.js";

const $ = (s) => document.querySelector(s);

const app = {
  file: null, info: null, project: newProject(null), analysis: null,
  effects: new Map(), effectList: [], sources: new Map(), registryVersion: 0,
  renderer: null, entries: new Map(), caps: null, exporting: null,
};
window.__sfx = app; // handy for debugging + headless tests

// ------------------------------------------------------------------ toasts
function toast(msg, cls = "", ttl = 5000) {
  const t = document.createElement("div"); t.className = "toast " + cls; t.textContent = msg;
  $("#toast-host").appendChild(t);
  requestAnimationFrame(() => t.classList.add("show"));
  setTimeout(() => { t.classList.remove("show"); setTimeout(() => t.remove(), 300); }, ttl);
}

// ------------------------------------------------------------------ registry
async function loadRegistry() {
  const res = await fetch(`${BASE}effects/index.json?v=${Date.now()}`);
  const idx = await res.json();
  app.registryVersion++;
  app.effectList = idx.effects;
  app.effects = new Map(idx.effects.map((e) => [e.id, e]));
  app.sources.clear();
  library.setEffects(app.effectList);
  // recompile anything in use
  for (const id of [...app.entries.keys()]) await ensureEntry(app.effects.get(id), true);
  timeline.render();
  requestDraw();
  refreshThumbs();
}

async function loadSources(effect) {
  const key = effect.id;
  if (app.sources.has(key)) return app.sources.get(key);
  const out = { __version: app.registryVersion, __textures: {} };
  for (const pass of effect.passes) {
    const r = await fetch(`${BASE}${effect.path}/${pass.file}?v=${app.registryVersion}`);
    out[pass.name] = await r.text();
    for (const ch of Object.values(pass.channels || {})) {
      if (!ch || typeof ch !== "object" || !ch.texture || out.__textures[ch.texture]) continue;
      try {
        const blob = await (await fetch(`${BASE}${effect.path}/${ch.texture}`)).blob();
        // WebGL ignores UNPACK_FLIP_Y for ImageBitmaps, so flip at decode time
        out.__textures[ch.texture] = await createImageBitmap(blob, { imageOrientation: "flipY" });
      } catch (err) { console.warn(`[effect ${effect.id}] texture ${ch.texture}`, err); }
    }
  }
  app.sources.set(key, out);
  return out;
}

async function ensureEntry(effect, force = false) {
  if (!effect) return null;
  if (!force && app.entries.has(effect.id)) return app.entries.get(effect.id);
  const entry = app.renderer.ensureEffect(effect, await loadSources(effect));
  app.entries.set(effect.id, entry);
  if (entry.error) {
    console.warn(`[effect ${effect.id}]`, entry.error);
    toast(`${effect.name} failed to compile:\n${entry.error.split("\n").slice(0, 4).join("\n")}`, "err", 9000);
  }
  return entry;
}

// ------------------------------------------------------------------ preview
const video = $("#video");
let drawQueued = false, sourceReady = false;

function currentTime() { return video.currentTime || 0; }

// mask tracks the renderer sees: baked tracks, plus the live SAM 2 selection preview
function maskTracksForRender() {
  const list = app.masks ? [...app.masks.tracks] : [];
  if (app.selectPreview) list.push(app.selectPreview);
  return list;
}
const frameIndexAt = (time) => Math.round((time - (app.info?.firstTs || 0)) * (app.info?.fps || 30));

function drawAt(time) {
  const R = app.renderer;
  if (!R || !app.info || !sourceReady) return;
  const frame = buildFrame(app.project, {
    time, index: frameIndexAt(time), dt: 1 / app.info.fps,
    analysis: app.analysis, effects: app.effects, entries: app.entries,
    maskTracks: maskTracksForRender(), overlayMask: app.selectPreview ? "__select" : app.maskOverlay,
  });
  R.render(frame);
  const L = frame.layers.map((l) => l.effect.name).join(" → ");
  $("#preview-info").textContent = L ? `fx: ${L}` : "";
}

function uploadVideoFrame() {
  if (video.readyState < 2) return false;
  app.renderer.uploadSource(video);
  sourceReady = true;
  return true;
}

function requestDraw() {
  if (drawQueued) return;
  drawQueued = true;
  const run = () => {
    drawQueued = false;
    if (!video.paused) return; // the frame callback drives drawing while playing
    if (uploadVideoFrame()) drawAt(currentTime());
  };
  // rAF stalls in background tabs; fall back to a timer so edits still land
  if (document.hidden) setTimeout(run, 0); else requestAnimationFrame(run);
}

function onVideoFrame(_now, meta) {
  if (uploadVideoFrame()) drawAt(meta.mediaTime);
  timeline.movePlayhead(meta.mediaTime, !video.paused);
  video.requestVideoFrameCallback(onVideoFrame);
}

function togglePlay() {
  if (!app.info || app.exporting) return;
  if (video.ended) video.currentTime = 0;
  video.paused ? video.play() : video.pause();
}
video.addEventListener("play", () => timeline.setPlaying(true));
video.addEventListener("pause", () => { timeline.setPlaying(false); requestDraw(); });
video.addEventListener("seeked", () => { timeline.movePlayhead(currentTime(), false); requestDraw(); });

function sizePreview() {
  if (!app.info) return;
  const half = $("#half-res").checked;
  const s = half ? 0.5 : 1;
  const w = Math.max(2, Math.round(app.info.width * s / 2) * 2), h = Math.max(2, Math.round(app.info.height * s / 2) * 2);
  app.renderer.resize(w, h);
  // renderer.resize drops per-segment feedback state; compiled programs survive
  requestDraw();
}
$("#half-res").addEventListener("change", sizePreview);

// ------------------------------------------------------------------ library + timeline + panel
const library = new Library({
  root: $("#library"),
  onAdd: (id) => { if (app.info) timeline.addAtPlayhead(id); },
});

const timeline = new Timeline({
  root: $("#timeline"),
  getProject: () => app.project,
  getEffect: (id) => app.effects.get(id),
  getTime: currentTime,
  onSeek: (t) => { video.currentTime = t; timeline.movePlayhead(t, false); },
  onScrubStart: () => { app._wasPlaying = !video.paused; video.pause(); },
  onScrubEnd: () => { if (app._wasPlaying) video.play(); },
  onSelect: () => {},
  onOpen: (seg) => panel.open(seg),
  onChange: async (kind, seg) => {
    if (seg && kind === "add") await ensureEntry(app.effects.get(seg.effectId));
    if (kind === "remove" && seg) { app.renderer.dropSegment(seg.id); if (panel.isOpenFor(seg)) panel.close(); }
    if (seg && panel.isOpenFor(seg)) panel.render();
    save(); requestDraw();
  },
});
timeline.el.play.addEventListener("click", togglePlay);

const panel = new SegmentModal({
  root: $("#seg-panel"),
  getEffect: (id) => app.effects.get(id),
  fps: () => app.info?.fps || 30,
  getMaskTracks: () => (app.masks ? app.masks.tracks.filter((t) => t.filled > 0).map((t) => ({ id: t.id, name: t.name })) : []),
  onChange: (seg) => { timeline.refreshSeg(seg); save(); requestDraw(); },
  onRemove: (seg) => timeline.removeSegment(seg),
  onDuplicate: (seg) => timeline.duplicateSegment(seg),
});

document.addEventListener("keydown", (e) => {
  if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === "s") { e.preventDefault(); if (app.info) (e.shiftKey ? projects.dialog({ saveAs: true }) : projects.save()); return; }
  const t = e.target, typing = t && (t.tagName === "INPUT" || t.tagName === "TEXTAREA" || t.tagName === "SELECT");
  if (typing) return;
  if (e.code === "Space") { e.preventDefault(); togglePlay(); }
  const sel = app.project.segments.find((s) => s.id === timeline.selectedId);
  if (sel && (e.key === "Delete" || e.key === "Backspace")) { e.preventDefault(); timeline.removeSegment(sel); }
  if (sel && (e.ctrlKey || e.metaKey) && e.key.toLowerCase() === "d") { e.preventDefault(); timeline.duplicateSegment(sel); }
  if (e.key === "ArrowRight" || e.key === "ArrowLeft") {
    if (!app.info) return;
    e.preventDefault(); video.pause();
    const step = (e.shiftKey ? 1 : 1 / app.info.fps) * (e.key === "ArrowRight" ? 1 : -1);
    video.currentTime = Math.max(0, Math.min(app.info.duration, currentTime() + step));
  }
});

let saveT = null;
function save() { projects.markDirty(); clearTimeout(saveT); saveT = setTimeout(() => autosave(app.project), 300); }

// ------------------------------------------------------------------ library thumbnails (from your video)
let thumbT = null, thumbMaker = null;
function refreshThumbs() {
  clearTimeout(thumbT);
  thumbT = setTimeout(async () => {
    if (!app.info || app.exporting) return;
    try {
      thumbMaker = thumbMaker || new ThumbMaker();
      const t = app.info.duration * 0.4;
      const source = await frameCanvasAt(app.file, t, THUMB_W, THUMB_H);
      if (!source) return;
      library.clearThumbs();
      await thumbMaker.run({
        source, effects: app.effectList, loadSources, time: t - (app.info.firstTs || 0), analysis: app.analysis,
        maskTracks: app.masks.tracks.filter((m) => m.filled === m.frames), frameIndex: frameIndexAt(t),
        onThumb: (id, url) => library.setThumb(id, url),
      });
    } catch (err) { console.warn("[thumbs]", err); }
  }, 700);
}

// ------------------------------------------------------------------ open video
async function openVideo(file, { project = null } = {}) {
  if (app.exporting) return;
  $("#drop-label").textContent = `probing ${file.name} …`;
  let info;
  try { info = await probeVideo(file); }
  catch (err) { $("#drop-label").textContent = `could not open ${file.name}: ${err.message}`; return; }
  app.file = file; app.info = info; app.analysis = null; sourceReady = false;
  app.maskOverlay = null; app.selectPreview = null;
  await app.masks.setVideo(file, info);
  const saved = project || loadAutosave(info);
  app.project = saved || newProject(info);
  if (!project) projects.setCurrent(null);
  app.project.video = { ...app.project.video, ...{ name: info.name, size: info.size, lastModified: info.lastModified, duration: info.duration, fps: info.fps, width: info.width, height: info.height } };
  for (const s of app.project.segments) await ensureEntry(app.effects.get(s.effectId));
  if (saved && saved.segments.length && !project) toast(`restored ${saved.segments.length} effect(s) from your last session on this video`);

  if (video.src) URL.revokeObjectURL(video.src);
  video.src = URL.createObjectURL(file);
  await new Promise((r) => video.addEventListener("loadeddata", r, { once: true }));
  video.requestVideoFrameCallback(onVideoFrame);
  sizePreview();
  uploadVideoFrame(); drawAt(0);

  $("#drop").classList.add("loaded");
  $("#timeline").classList.remove("locked");
  $("#btn-export").disabled = false; $("#btn-save").disabled = false;
  const a = info.audio ? `${info.audio.codecString} ${info.audio.sampleRate / 1000}k` : "no audio";
  $("#video-meta").textContent = `${info.name} · ${info.width}×${info.height} · ${info.fps}fps · ${info.duration.toFixed(2)}s · ${info.codec} · ${a}`;
  timeline.setMedia({ duration: info.duration, analysis: null });
  if (!info.audio) refreshThumbs(); // otherwise after the audio analysis lands

  // background: thumbnails + audio analysis
  (async () => {
    timeline.clearThumbs();
    const count = Math.max(8, Math.min(60, Math.round(info.duration / 2)));
    try { for await (const th of thumbnails(file, count, 40)) timeline.addThumb(th.time, th.canvas); } catch (err) { console.warn("thumbs", err); }
  })();
  analyse(file);
}

async function analyse(file) {
  const meta = $("#video-meta");
  const base = meta.textContent;
  if (!app.info.audio) return;
  meta.textContent = base + " · decoding audio…";
  const dec = await decodeMonoAudio(file);
  if (!dec) return;
  const worker = new Worker(new URL("./audio/analysis.worker.js", import.meta.url), { type: "module" });
  worker.onmessage = (e) => {
    const m = e.data;
    if (m.type === "progress") meta.textContent = `${base} · analysing audio ${Math.round(m.p * 100)}%`;
    else if (m.type === "done") {
      app.analysis = m.analysis;
      meta.textContent = `${base} · ${m.analysis.bpm.toFixed(1)} bpm · ${m.analysis.beats.length} beats`;
      timeline.setAnalysis(m.analysis); requestDraw(); worker.terminate(); refreshThumbs();
    } else if (m.type === "error") { meta.textContent = base + " · audio analysis failed"; toast("audio analysis failed: " + m.message, "err"); worker.terminate(); }
  };
  worker.postMessage({ mono: dec.mono, sampleRate: dec.sampleRate }, [dec.mono.buffer]);
}

// drop / click to open
const wrap = $("#preview-wrap"), drop = $("#drop"), vinput = $("#video-input");
drop.addEventListener("click", () => vinput.click());
$("#btn-open").addEventListener("click", () => vinput.click());
vinput.addEventListener("change", (e) => { if (e.target.files[0]) openVideo(e.target.files[0]); e.target.value = ""; });
wrap.addEventListener("dragover", (e) => { if (e.dataTransfer.types.includes("Files")) { e.preventDefault(); wrap.classList.add("dragover"); drop.classList.add("hover"); } });
wrap.addEventListener("dragleave", () => { wrap.classList.remove("dragover"); drop.classList.remove("hover"); });
wrap.addEventListener("drop", (e) => {
  e.preventDefault(); wrap.classList.remove("dragover"); drop.classList.remove("hover");
  const f = e.dataTransfer.files[0]; if (f) openVideo(f);
});

// ------------------------------------------------------------------ project save / load
// named projects live in Documents/Sizzle FX (server/projects.py); .json export/import stays as a fallback
const projects = new ProjectLibrary({
  app, toast,
  openVideo: (file, opts) => openVideo(file, opts),
  applyProject: (p) => applyProject(p),
  onState: (busyMsg) => {
    const n = projects.name;
    $("#proj-label").textContent = busyMsg || (n ? `${n}${projects.dirty ? " •" : ""}` : (app.info ? "unsaved project" : ""));
    if (HOSTED) { $("#proj-label").textContent = busyMsg || ""; document.title = "SIZZLE FX"; return; }
    $("#proj-label").title = n ? `project "${n}" in Documents\\Sizzle FX\\Projects${projects.dirty ? " (unsaved changes, ctrl+s)" : ""}` : "not saved yet: ctrl+s or projects → save";
    document.title = (n ? `${n}${projects.dirty ? " •" : ""} · ` : "") + "SIZZLE FX";
  },
});
app.projects = projects;
$("#btn-projects").addEventListener("click", () => projects.dialog());
$("#btn-save").addEventListener("click", () => projects.save());
if (HOSTED) {
  // no local server on the web build: "save" downloads the timeline as .json
  $("#btn-save").textContent = "save .json";
  $("#btn-save").title = "download this timeline as a .sfx.json file (ctrl+s); projects with video + masks need the desktop install";
  $("#btn-projects").title = "export / import timeline .json";
}
window.addEventListener("beforeunload", (e) => { if (projects.dirty && projects.name) { e.preventDefault(); e.returnValue = ""; } });

async function applyProject(p) {
  if (app.info && p.video && p.video.name !== app.info.name) toast(`project was made for ${p.video.name}; applying it to ${app.info.name}`, "warn");
  p.video = app.project.video || p.video;
  app.project = p;
  for (const s of p.segments) await ensureEntry(app.effects.get(s.effectId));
  timeline.render(); autosave(app.project); requestDraw();
}

$("#btn-export-json").addEventListener("click", () => {
  const blob = new Blob([serialise(app.project)], { type: "application/json" });
  const a = document.createElement("a");
  a.href = URL.createObjectURL(blob);
  a.download = (app.info?.name || "project").replace(/\.[^.]+$/, "") + ".sfx.json";
  a.click(); setTimeout(() => URL.revokeObjectURL(a.href), 2000);
});
$("#project-input").addEventListener("change", async (e) => {
  const f = e.target.files[0]; e.target.value = "";
  if (!f) return;
  try {
    const p = deserialise(await f.text());
    await applyProject(p); projects.markDirty();
    toast(`loaded ${p.segments.length} effect(s)`);
  } catch (err) { toast("could not load project: " + err.message, "err"); }
});

// ------------------------------------------------------------------ export
const presetSel = $("#export-preset");
for (const [k, p] of Object.entries(PRESETS)) { const o = document.createElement("option"); o.value = k; o.textContent = p.label; presetSel.appendChild(o); }

$("#btn-export").addEventListener("click", () => doExport());

async function doExport() {
  if (!app.info || app.exporting) return null;
  if (!app.analysis && app.info.audio) { toast("audio analysis is still running, export when it finishes", "warn"); return null; }
  if (app.masks.busy) { toast("a mask is still baking, export when it finishes", "warn"); return null; }
  video.pause();
  const ctl = new AbortController();
  app.exporting = ctl;
  document.body.classList.add("rendering");
  $("#btn-export").disabled = true;
  $("#progress").classList.remove("hidden"); $("#result").classList.add("hidden");
  const fill = $("#progress-fill"), log = $("#progress-log");
  const t0 = performance.now();
  try {
    const onProgress = (p, msg) => { fill.style.width = (p * 100).toFixed(1) + "%"; log.textContent = msg; };
    const maskTracks = app.masks.tracks.filter((t) => t.filled > 0);
    const viaServer = $("#render-mode").value === "server";
    const { blob, stats } = viaServer
      ? await serverExport({ file: app.file, info: app.info, project: app.project, analysis: app.analysis, maskTracks,
          preset: presetSel.value, signal: ctl.signal, onProgress })
      : await exportVideo({
          file: app.file, info: app.info, project: app.project, effects: app.effects, loadSources,
          analysis: app.analysis, preset: PRESETS[presetSel.value], signal: ctl.signal, maskTracks, onProgress,
        });
    app.lastExport = { blob, stats };
    const url = URL.createObjectURL(blob);
    const dl = $("#download");
    dl.href = url; dl.download = app.info.name.replace(/\.[^.]+$/, "") + "_sizzlefx.mp4";
    const secs = ((performance.now() - t0) / 1000).toFixed(1);
    $("#result-meta").textContent = `${stats.width}×${stats.height} · ${stats.frames} frames · ${(stats.bytes / 1e6).toFixed(1)} MB · ${stats.codec} ${stats.bitrateMode || ""} · audio ${stats.audioMode} · ${secs}s`;
    $("#result").classList.remove("hidden");
    return app.lastExport;
  } catch (err) {
    if (err.name === "AbortError") toast("export cancelled", "warn");
    else { console.error(err); toast("export failed: " + err.message, "err", 10000); }
    app.lastError = err;
    return null;
  } finally {
    app.exporting = null;
    document.body.classList.remove("rendering");
    $("#btn-export").disabled = false;
    $("#progress").classList.add("hidden");
  }
}
Object.assign(app, { openVideo, doExport, timeline, panel, drawAt, requestDraw, uploadVideoFrame });
$("#btn-cancel").addEventListener("click", () => app.exporting?.abort());

// ------------------------------------------------------------------ masks
let maskDrawT = 0;
app.masks = new MaskManager({
  onChange: () => {
    maskPanel.render(); if (panel.seg) panel.render(); requestDraw();
    // the first finished mask changes what Body-effect thumbnails look like
    const sig = app.masks.tracks.filter((t) => t.filled === t.frames).map((t) => t.id).join(",");
    if (sig !== app._maskSig) { app._maskSig = sig; refreshThumbs(); }
  },
  // redraw at most ~8x/s while a bake streams frames in
  onFrame: () => { const n = performance.now(); if (n - maskDrawT > 120) { maskDrawT = n; requestDraw(); } },
  onStatus: (t, msg) => maskPanel.setStatus(t, msg),
});
const maskPanel = new MaskPanel({
  root: $("#mask-panel"), button: $("#btn-masks"), canvas: $("#preview"), manager: app.masks, toast,
  getFrameIndex: () => frameIndexAt(currentTime()),
  onOverlay: (id) => { app.maskOverlay = id; requestDraw(); },
  onSelectPreview: (t) => { app.selectPreview = t; requestDraw(); },
});
app.maskPanel = maskPanel;

// ------------------------------------------------------------------ boot
async function boot() {
  app.renderer = new Renderer($("#preview"));
  await loadRegistry();
  app.caps = await detectCapabilities();
  const c = app.caps;
  const g = $("#badge-gpu");
  g.textContent = c.webgl2 ? `gpu: ${c.gpu.replace(/^ANGLE \((.*)\)$/, "$1").split(",")[1]?.trim() || c.gpu}` : "gpu: no webgl2";
  g.className = "badge " + (c.webgl2 && c.floatTargets ? "ok" : c.webgl2 ? "warn" : "bad");
  g.title = `${c.gpu}\nfloat targets: ${c.floatTargets}\nwebgpu: ${c.webgpu}`;
  const enc = $("#badge-enc");
  enc.textContent = c.h264High ? "h.264 high: ok" : "h.264 high: missing";
  enc.className = "badge " + (c.h264High ? "ok" : "bad");
  enc.title = `AAC encoder: ${c.aacEncode ? "browser" : "wasm fallback"}`;
  const modeSel = $("#render-mode");
  const srvOpt = modeSel.querySelector('option[value="server"]');
  if (c.server) { srvOpt.disabled = false; srvOpt.textContent = "server gpu (python)"; }
  modeSel.title = c.server ? `browser: WebGL2 + WebCodecs here · server: ${c.serverInfo?.gpu || "python"} + ffmpeg (${c.serverInfo?.nvenc ? "NVENC" : "x264"})`
    : HOSTED ? "server rendering comes with the desktop install (see the GitHub repo)" : "start server\\start.bat to enable server rendering";
  if (HOSTED) srvOpt.textContent = "server gpu (desktop install)";
  try { const saved = localStorage.getItem("sizzlefx:renderMode"); if (saved === "server" && c.server) modeSel.value = "server"; else modeSel.value = chooseDefaultMode(c); }
  catch (_) { modeSel.value = chooseDefaultMode(c); }
  modeSel.addEventListener("change", () => { try { localStorage.setItem("sizzlefx:renderMode", modeSel.value); } catch (_) {} });
}
// ?project=<name> opens a saved project straight away (a link to hand someone a ready project)
boot().then(() => {
  const name = new URLSearchParams(location.search).get("project");
  if (name && !HOSTED) projects.open(name);
});

if (import.meta.hot) import.meta.hot.on("effects-changed", (d) => { loadRegistry(); toast(`effects updated (${d.file})`, "", 2500); });
