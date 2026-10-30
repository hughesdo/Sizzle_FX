// Mask baking off the main thread. Providers:
//   key  : chroma key (green/blue screen), CPU, instant
//   rvm  : Robust Video Matting, recurrent, automatic people (WebGPU)
//   sam2 : SAM 2.1 tiny, click-to-select anything; tracked frame to frame by
//          re-prompting each frame with the previous mask's box + interior point
// Frames are decoded with Mediabunny, so frame i here == frame i in preview/export.
//
// in : {type:"bake", file, provider, width, height, fps, firstTs, frames, params, prompt?}
//      {type:"sam2-select", file, frameIndex, fps, firstTs, width, height, points:[{x,y,label}]}
//      {type:"cancel"}
// out: {type:"status", msg} {type:"frame", i, alpha} {type:"progress", done, total, fps}
//      {type:"select", alpha, score, ms} {type:"done", frames} {type:"error", message}

import { Input, BlobSource, ALL_FORMATS, CanvasSink } from "mediabunny";
import { createSession } from "./ort.js";

let cancelled = false;
const post = (m, t) => self.postMessage(m, t || []);

self.onmessage = async (e) => {
  const m = e.data;
  if (m.type === "cancel") { cancelled = true; return; }
  cancelled = false;
  try {
    if (m.type === "bake") await bake(m);
    else if (m.type === "sam2-select") await samSelect(m);
    else if (m.type === "sam2-probe") await samProbe(m);
  } catch (err) {
    post({ type: "error", message: String(err && err.message || err) });
  }
};

function openTrack(file) {
  const input = new Input({ source: new BlobSource(file), formats: ALL_FORMATS });
  return input.getPrimaryVideoTrack();
}
const idxOf = (ts, m) => Math.round((ts - (m.firstTs || 0)) * m.fps);
const tsOf = (i, m) => (m.firstTs || 0) + i / m.fps;

function imageData(canvas) {
  return canvas.getContext("2d", { willReadFrequently: true }).getImageData(0, 0, canvas.width, canvas.height);
}

// ------------------------------------------------------------------ key
function rgbToCbCr(r, g, b) { return [-0.168736 * r - 0.331264 * g + 0.5 * b, 0.5 * r - 0.418688 * g - 0.081312 * b]; }

function autoKey(img) {
  // median chroma of the frame border (the backdrop almost always touches it)
  const { data, width: w, height: h } = img;
  const cbs = [], crs = [];
  const take = (x, y) => { const k = (y * w + x) * 4; const [cb, cr] = rgbToCbCr(data[k], data[k + 1], data[k + 2]); cbs.push(cb); crs.push(cr); };
  for (let x = 0; x < w; x += 2) { take(x, 0); take(x, 1); }
  for (let y = 0; y < h * 0.6; y += 2) { take(0, y); take(w - 1, y); take(1, y); take(w - 2, y); }
  const med = (a) => a.sort((p, q) => p - q)[a.length >> 1];
  return [med(cbs), med(crs)];
}

function keyAlpha(img, key, p) {
  const { data, width: w, height: h } = img;
  const n = w * h, out = new Uint8Array(n);
  const tol = (p.tolerance ?? 0.12) * 180, soft = Math.max(1, (p.softness ?? 0.1) * 180);
  for (let i = 0; i < n; i++) {
    const k = i * 4;
    const [cb, cr] = rgbToCbCr(data[k], data[k + 1], data[k + 2]);
    const d = Math.hypot(cb - key[0], cr - key[1]);
    const a = (d - tol) / soft;
    out[i] = a <= 0 ? 0 : a >= 1 ? 255 : Math.round(a * 255);
  }
  clearEdgeBars(out, img.width, img.height);
  return out;
}

// Letterbox / pillarbox bars (black or blended) get keyed / segmented as "subject"
// (SAM even glues them onto a dark jacket that touches them). Within 4% of each edge,
// a column that is >= 70% opaque, or a row >= 95% opaque, is a bar, not a person
// (people touch an edge, they don't fill it): clear it and keep walking in.
function clearEdgeBars(out, w, h) {
  const mx = Math.ceil(w * 0.04), my = Math.ceil(h * 0.04);
  const colFrac = (x) => { let n = 0; for (let y = 0; y < h; y++) n += out[y * w + x] > 127; return n / h; };
  const rowFrac = (y) => { let n = 0; for (let x = 0; x < w; x++) n += out[y * w + x] > 127; return n / w; };
  for (const left of [true, false]) {
    let cleared = 0;
    for (let s = 0; s < mx; s++) {
      const x = left ? s : w - 1 - s, f = colFrac(x);
      if (f < 0.05) continue;                       // already background, keep walking
      const bar = f >= (s < w * 0.015 ? 0.4 : 0.7); // the outermost 1.5%: a partial bar counts too
      if (bar || cleared) for (let y = 0; y < h; y++) out[y * w + x] = 0; // bar, or 1px soft edge after one
      if (!bar) break;
      cleared++;
    }
  }
  for (const top of [true, false]) for (let s = 0; s < my; s++) {
    const y = top ? s : h - 1 - s, f = rowFrac(y);
    if (f < 0.05) continue;
    if (f < 0.95) break;
    out.fill(0, y * w, y * w + w);
  }
}

// ------------------------------------------------------------------ RVM
async function rvmRunner(p) {
  post({ type: "status", msg: "loading RVM model…" });
  const { ort, session } = await createSession("rvm");
  const zero = () => new ort.Tensor("float32", new Float32Array([0]), [1, 1, 1, 1]);
  let rec = [zero(), zero(), zero(), zero()];
  const ratio = new ort.Tensor("float32", new Float32Array([p.downsample ?? 0.5]), [1]);
  return async (img) => {
    const { data, width: w, height: h } = img;
    const n = w * h, src = new Float32Array(3 * n);
    for (let i = 0; i < n; i++) { const k = i * 4; src[i] = data[k] / 255; src[n + i] = data[k + 1] / 255; src[2 * n + i] = data[k + 2] / 255; }
    const res = await session.run({ src: new ort.Tensor("float32", src, [1, 3, h, w]), r1i: rec[0], r2i: rec[1], r3i: rec[2], r4i: rec[3], downsample_ratio: ratio },
      ["pha", "r1o", "r2o", "r3o", "r4o"]);
    rec = [res.r1o, res.r2o, res.r3o, res.r4o];
    const pha = res.pha.data, out = new Uint8Array(n);
    for (let i = 0; i < n; i++) out[i] = Math.max(0, Math.min(255, Math.round(pha[i] * 255)));
    clearEdgeBars(out, w, h);
    return out;
  };
}

// ------------------------------------------------------------------ SAM2
const SAM = 1024;
let sam = null;
async function samLoad() {
  if (sam) return sam;
  post({ type: "status", msg: "loading SAM 2.1 (first time ~155 MB)…" });
  const enc = await createSession("sam2Encoder");
  // decoder on the GPU too: on wasm it was ~350 ms per prompt (the bottleneck)
  const dec = await createSession("sam2Decoder");
  sam = { ort: enc.ort, enc: enc.session, dec: dec.session, cache: null };
  return sam;
}

async function samEncode(img1024, key) {
  const s = await samLoad();
  if (key != null && s.cache && s.cache.key === key) return s.cache.emb;
  const { data } = img1024, n = SAM * SAM, px = new Float32Array(3 * n);
  const mean = [0.485, 0.456, 0.406], std = [0.229, 0.224, 0.225];
  for (let i = 0; i < n; i++) {
    const k = i * 4;
    px[i] = (data[k] / 255 - mean[0]) / std[0];
    px[n + i] = (data[k + 1] / 255 - mean[1]) / std[1];
    px[2 * n + i] = (data[k + 2] / 255 - mean[2]) / std[2];
  }
  const out = await s.enc.run({ pixel_values: new s.ort.Tensor("float32", px, [1, 3, SAM, SAM]) });
  const emb = [out["image_embeddings.0"], out["image_embeddings.1"], out["image_embeddings.2"]];
  s.cache = { key, emb };
  return emb;
}

// points: [{x,y,label}] in 1024 space; box: [x0,y0,x1,y1] in 1024 space or null.
// prev (tracking): {alpha, w, h} last frame's mask; pick the reading that overlaps it most.
// level (selection): 0 = whole (largest reading), 1 = part, 2 = detail.
async function samDecode(emb, points, box, prev = null, level = 0) {
  const s = sam, T = s.ort.Tensor;
  const pts = points.length ? points : [{ x: 0, y: 0, label: -10 }];
  const feeds = {
    "image_embeddings.0": emb[0], "image_embeddings.1": emb[1], "image_embeddings.2": emb[2],
    input_points: new T("float32", Float32Array.from(pts.flatMap((p) => [p.x, p.y])), [1, 1, pts.length, 2]),
    input_labels: new T("int64", BigInt64Array.from(pts.map((p) => BigInt(p.label))), [1, 1, pts.length]),
  };
  if (box) feeds.input_boxes = new T("float32", Float32Array.from(box), [1, 1, 4]);
  else feeds.input_boxes = new T("float32", new Float32Array(0), [1, 0, 4]);
  const r = await s.dec.run(feeds);
  const iou = r.iou_scores.data, masks = r.pred_masks, dims = masks.dims;
  const nm = dims[2], mh = dims[3], mw = dims[4];
  // SAM returns three readings (whole / part / sub-part) with predicted IoUs. Max-IoU
  // picks e.g. just the face for a face click, and the IoUs differ a lot between the
  // GPU and CPU decoders (whole person: 0.11 vs 0.24), so selection ranks readings by
  // AREA and the user picks whole/part/detail. While tracking, "largest" would feed
  // back through the growing box and leak into the background, so there we score
  // confidence minus size change instead.
  const areas = [];
  for (let k = 0; k < nm; k++) {
    let area = 0; const o = k * mh * mw;
    for (let i = 0; i < mh * mw; i++) area += masks.data[o + i] > 0;
    areas.push(area / (mh * mw));
  }
  let best = 0, overlap = 1;
  if (prev && prev.alpha) {
    // temporal consistency: mask IoU of each reading with last frame's mask
    let bs = -1e9;
    for (let k = 0; k < nm; k++) {
      let inter = 0, uni = 0; const o = k * mh * mw;
      for (let y = 0; y < mh; y++) {
        const py = Math.min(prev.h - 1, Math.floor((y + 0.5) / mh * prev.h)) * prev.w;
        for (let x = 0; x < mw; x++) {
          const a = masks.data[o + y * mw + x] > 0, b = prev.alpha[py + Math.min(prev.w - 1, Math.floor((x + 0.5) / mw * prev.w))] > 127;
          if (a && b) inter++; if (a || b) uni++;
        }
      }
      const mi = uni ? inter / uni : 0;
      const s = mi + 0.15 * iou[k];
      if (s > bs) { bs = s; best = k; overlap = mi; }
    }
  } else {
    const order = areas.map((a, k) => k).sort((p, q) => areas[q] - areas[p]);
    best = order[Math.max(0, Math.min(order.length - 1, level))];
  }
  const obj = r.object_score_logits ? r.object_score_logits.data[0] : 1;
  return { logits: masks.data.subarray(best * mh * mw, (best + 1) * mh * mw), mw, mh, score: iou[best], present: obj > 0, area: areas[best], overlap,
    candidates: areas.map((a, k) => ({ area: +a.toFixed(3), iou: +iou[k].toFixed(3) })) };
}

// low-res logits (full frame, stretched) -> soft alpha at mask res
function logitsToAlpha(L, mw, mh, w, h, present) {
  const out = new Uint8Array(w * h);
  if (!present) return out;
  for (let y = 0; y < h; y++) {
    const fy = (y + 0.5) / h * mh - 0.5, y0 = Math.max(0, Math.floor(fy)), y1 = Math.min(mh - 1, y0 + 1), ty = Math.min(1, Math.max(0, fy - y0));
    for (let x = 0; x < w; x++) {
      const fx = (x + 0.5) / w * mw - 0.5, x0 = Math.max(0, Math.floor(fx)), x1 = Math.min(mw - 1, x0 + 1), tx = Math.min(1, Math.max(0, fx - x0));
      const v = (L[y0 * mw + x0] * (1 - tx) + L[y0 * mw + x1] * tx) * (1 - ty) + (L[y1 * mw + x0] * (1 - tx) + L[y1 * mw + x1] * tx) * ty;
      out[y * w + x] = Math.round(255 / (1 + Math.exp(-v * 2.5)));
    }
  }
  return out;
}

// prompt for the next frame from this frame's alpha: expanded bbox + interior point
function promptFrom(alpha, w, h) {
  let x0 = w, y0 = h, x1 = -1, y1 = -1, sx = 0, sy = 0, n = 0;
  for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) if (alpha[y * w + x] > 127) {
    if (x < x0) x0 = x; if (x > x1) x1 = x; if (y < y0) y0 = y; if (y > y1) y1 = y; sx += x; sy += y; n++;
  }
  if (!n) return null;
  let cx = sx / n, cy = sy / n;
  if (alpha[Math.round(cy) * w + Math.round(cx)] <= 127) {
    // centroid outside the shape (e.g. a C pose): nearest inside pixel
    let bd = 1e9;
    for (let y = y0; y <= y1; y += 2) for (let x = x0; x <= x1; x += 2) if (alpha[y * w + x] > 127) {
      const d = (x - cx) ** 2 + (y - cy) ** 2; if (d < bd) { bd = d; var bx = x, by = y; }
    }
    cx = bx; cy = by;
  }
  // small margin: a big one lets the mask creep outward a little more every frame
  const mx = (x1 - x0) * 0.04 + 3, my = (y1 - y0) * 0.04 + 3;
  const S = (v, d) => Math.max(0, Math.min(SAM, v / d * SAM));
  const bx0 = Math.max(0, x0 - mx), by0 = Math.max(0, y0 - my), bx1 = Math.min(w - 1, x1 + mx), by1 = Math.min(h - 1, y1 + my);
  // negative points: box corners that are background in this frame.
  // (Tried and measured worse on the Rave clip vs RVM: a 6x4 grid of background
  // negatives + dropping the box when it covers >60% of the frame: mean IoU 0.64.)
  const negs = [];
  for (const [x, y] of [[bx0, by0], [bx1, by0], [bx0, by1], [bx1, by1]]) {
    const xi = Math.round(x), yi = Math.round(y);
    if (alpha[yi * w + xi] < 40) negs.push({ x: S(xi + 0.5, w), y: S(yi + 0.5, h), label: 0 });
  }
  return {
    box: [S(bx0, w), S(by0, h), S(bx1 + 1, w), S(by1 + 1, h)],
    points: [{ x: S(cx + 0.5, w), y: S(cy + 0.5, h), label: 1 }, ...negs],
    rect: [bx0, by0, bx1, by1],
  };
}

// keep the mask inside a slightly grown copy of last frame's box (stops leaks)
function clipToRect(alpha, w, h, rect) {
  const [x0, y0, x1, y1] = rect, gx = (x1 - x0) * 0.12 + 6, gy = (y1 - y0) * 0.12 + 6;
  const a = Math.max(0, Math.floor(x0 - gx)), b = Math.min(w, Math.ceil(x1 + gx)), c = Math.max(0, Math.floor(y0 - gy)), d = Math.min(h, Math.ceil(y1 + gy));
  for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) if (x < a || x >= b || y < c || y >= d) alpha[y * w + x] = 0;
}

async function frameAt(track, i, m, sink) {
  const wc = await sink.getCanvas(tsOf(i, m) + 0.25 / m.fps);
  return wc ? wc.canvas : null;
}

async function samSelect(m) {
  const t0 = performance.now();
  await samLoad();
  const vt = await openTrack(m.file);
  const sink = new CanvasSink(vt, { width: SAM, height: SAM, fit: "fill" });
  const canvas = await frameAt(vt, m.frameIndex, m, sink);
  if (!canvas) throw new Error("could not decode that frame");
  const t1 = performance.now();
  const emb = await samEncode(imageData(canvas), `${m.file.name}:${m.frameIndex}`);
  const t2 = performance.now();
  const pts = m.points.map((p) => ({ x: p.x * SAM, y: p.y * SAM, label: p.label }));
  const d = await samDecode(emb, pts, null, null, m.level || 0);
  const t3 = performance.now();
  const alpha = logitsToAlpha(d.logits, d.mw, d.mh, m.width, m.height, true);
  clearEdgeBars(alpha, m.width, m.height);
  post({ type: "select", alpha, score: d.score, ms: Math.round(performance.now() - t0),
    timing: { decodeFrame: Math.round(t1 - t0), encode: Math.round(t2 - t1), prompt: Math.round(t3 - t2) }, candidates: d.candidates }, [alpha.buffer]);
}

// debugging aid: candidates for several prompt variants on one frame
async function samProbe(m) {
  await samLoad();
  const vt = await openTrack(m.file);
  const sink = new CanvasSink(vt, { width: SAM, height: SAM, fit: "fill" });
  const emb = await samEncode(imageData(await frameAt(vt, m.frameIndex, m, sink)), `${m.file.name}:${m.frameIndex}`);
  const out = {};
  for (const [name, v] of Object.entries(m.variants)) {
    const pts = (v.points || []).map((p) => ({ x: p.x * SAM, y: p.y * SAM, label: p.label }));
    const box = v.box ? v.box.map((c) => c * SAM) : null;
    try { out[name] = (await samDecode(emb, pts, box, null, 0)).candidates; } catch (err) { out[name] = String(err.message || err); }
  }
  post({ type: "select", probe: out });
}

// ------------------------------------------------------------------ bake
async function bake(m) {
  const vt = await openTrack(m.file);
  const W = m.width, H = m.height, total = m.frames, p = m.params || {};
  let done = 0; const t0 = performance.now();
  const emit = (i, alpha) => {
    post({ type: "frame", i, alpha }, [alpha.buffer]);
    done++;
    if (done % 3 === 0 || done === total) post({ type: "progress", done, total, fps: done / ((performance.now() - t0) / 1000) });
  };

  if (m.provider === "key" || m.provider === "rvm") {
    const sink = new CanvasSink(vt, { width: W, height: H, fit: "fill" });
    const run = m.provider === "rvm" ? await rvmRunner(p) : null;
    let key = p.keyColor ? p.keyColor : null;
    post({ type: "status", msg: m.provider === "rvm" ? "matting…" : "keying…" });
    for await (const wc of sink.canvases()) {
      if (cancelled) throw new Error("cancelled");
      const i = idxOf(wc.timestamp, m);
      if (i < 0 || i >= total) continue;
      const img = imageData(wc.canvas);
      if (run) emit(i, await run(img));
      else { if (!key) key = autoKey(img); emit(i, keyAlpha(img, key, p)); }
    }
  } else if (m.provider === "sam2") {
    await samLoad();
    firstPrompt = null;
    const f0 = m.prompt.frameIndex;
    const userPts = m.prompt.points.map((q) => ({ x: q.x * SAM, y: q.y * SAM, label: q.label }));
    const sink = new CanvasSink(vt, { width: SAM, height: SAM, fit: "fill" });
    const step = async (img, i, prompt) => {
      const emb = await samEncode(img, null);
      let alpha, area;
      if (prompt.user) {
        const d = await samDecode(emb, prompt.user, null, null, m.prompt.level || 0);
        alpha = logitsToAlpha(d.logits, d.mw, d.mh, W, H, true); area = d.area;
        clearEdgeBars(alpha, W, H);
      } else {
        const d = await samDecode(emb, prompt.points, prompt.box, { alpha: prompt.alpha, w: W, h: H });
        alpha = logitsToAlpha(d.logits, d.mw, d.mh, W, H, d.present); area = d.area;
        clipToRect(alpha, W, H, prompt.rect);
        clearEdgeBars(alpha, W, H);
        // Nothing resembles last frame (jumped to the background): hold last frame's mask.
        // Measured on the Rave clip vs RVM, this is the best of five variants (mean IoU
        // 0.83, worst 0.53 while it held a stale pose through the fastest arm swing);
        // capping the hold at 2 frames or never holding collapsed to 0 around frame 115.
        if (prompt.alpha && (d.overlap < 0.45 || (area > prompt.area * 1.7 && area - prompt.area > 0.06))) { alpha = prompt.alpha.slice(); area = prompt.area; }
      }
      const next = promptFrom(alpha, W, H);
      if (next) { next.area = area; next.alpha = alpha.slice(); }
      emit(i, alpha);
      return next || prompt; // object lost: keep searching with the last good prompt
    };
    post({ type: "status", msg: "tracking forward…" });
    // forward: f0 .. end
    let prompt = { user: userPts };
    for await (const wc of sink.canvases(tsOf(f0, m) - 0.25 / m.fps)) {
      if (cancelled) throw new Error("cancelled");
      const i = idxOf(wc.timestamp, m);
      if (i < f0 || i >= total) continue;
      prompt = await step(imageData(wc.canvas), i, prompt);
      if (prompt.user && i > f0) delete prompt.user;
      if (i === f0) firstPrompt = prompt;
    }
    // backward: f0-1 .. 0, in decoded chunks played in reverse
    post({ type: "status", msg: "tracking backward…" });
    prompt = firstPrompt && !firstPrompt.user ? firstPrompt : prompt;
    const CH = 32;
    for (let hi = f0; hi > 0; hi -= CH) {
      const lo = Math.max(0, hi - CH), chunk = [];
      for await (const wc of sink.canvases(tsOf(lo, m) - 0.25 / m.fps, tsOf(hi, m) - 0.25 / m.fps)) {
        const i = idxOf(wc.timestamp, m);
        if (i >= lo && i < hi) chunk.push({ i, img: imageData(wc.canvas) });
      }
      for (let k = chunk.length - 1; k >= 0; k--) {
        if (cancelled) throw new Error("cancelled");
        prompt = await step(chunk[k].img, chunk[k].i, prompt);
      }
    }
  } else throw new Error("unknown provider " + m.provider);
  post({ type: "done", frames: done });
}
let firstPrompt = null;
