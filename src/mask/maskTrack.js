// A mask track = one 8-bit alpha frame per source frame (subject = 255), plus
// per-frame stats (centroid, bbox, area) for effects that orbit/rotate around
// the subject. Baked once by a provider (key / RVM / SAM2), kept in RAM, and
// persisted gzipped in OPFS so a reload doesn't need a re-bake.

export const MASK_LONG_SIDE = 640;
const MEMORY_BUDGET = 600 * 1024 * 1024; // bytes of R8 frames held in RAM per track
const STAT_N = 7; // cx, cy, x0, y0, x1, y1, area   (uv space, origin bottom-left)

// Mask resolution for a video: long side 640, multiples of 32 (RVM's pools must see
// even sizes, see ort.js), shrunk if the whole track would not fit the RAM budget.
export function maskSize(info) {
  const long = Math.max(info.width, info.height);
  let s = Math.min(1, MASK_LONG_SIDE / long);
  const frames = Math.max(1, info.frames);
  const per = (info.width * s) * (info.height * s);
  if (per * frames > MEMORY_BUDGET) s *= Math.sqrt(MEMORY_BUDGET / (per * frames));
  const r32 = (v) => Math.max(64, Math.floor(v * s / 32) * 32); // floor: never over budget
  return { width: r32(info.width), height: r32(info.height) };
}

export class MaskTrack {
  constructor({ id, name, provider, width, height, frames, params = {} }) {
    Object.assign(this, { id, name, provider, width, height, frames, params });
    this.data = new Uint8Array(width * height * frames);
    this.stats = new Float32Array(frames * STAT_N);
    this.filled = 0; // frames written so far (a bake in progress shows partial results)
  }

  frame(i) {
    const k = Math.max(0, Math.min(this.frames - 1, i));
    const n = this.width * this.height;
    return this.data.subarray(k * n, k * n + n);
  }

  statsAt(i) {
    const k = Math.max(0, Math.min(this.frames - 1, i)) * STAT_N, s = this.stats;
    return { centroid: [s[k], s[k + 1]], bbox: [s[k + 2], s[k + 3], s[k + 4], s[k + 5]], area: s[k + 6] };
  }

  // alpha: Uint8Array w*h, rows top-down (canvas order)
  setFrame(i, alpha) {
    if (i < 0 || i >= this.frames) return;
    const w = this.width, h = this.height;
    this.data.set(alpha, i * w * h);
    let sum = 0, sx = 0, sy = 0, x0 = w, y0 = h, x1 = -1, y1 = -1;
    for (let y = 0; y < h; y++) {
      const row = y * w;
      for (let x = 0; x < w; x++) {
        const a = alpha[row + x];
        if (a < 8) continue;
        sum += a; sx += a * x; sy += a * y;
        if (a > 127) { if (x < x0) x0 = x; if (x > x1) x1 = x; if (y < y0) y0 = y; if (y > y1) y1 = y; }
      }
    }
    const k = i * STAT_N, s = this.stats;
    if (sum > 0) {
      // flip y into GL uv space (origin bottom-left)
      s[k] = (sx / sum + 0.5) / w; s[k + 1] = 1 - (sy / sum + 0.5) / h;
      if (x1 >= 0) { s[k + 2] = x0 / w; s[k + 3] = 1 - (y1 + 1) / h; s[k + 4] = (x1 + 1) / w; s[k + 5] = 1 - y0 / h; }
      else { s[k + 2] = s[k]; s[k + 3] = s[k + 1]; s[k + 4] = s[k]; s[k + 5] = s[k + 1]; }
      s[k + 6] = sum / 255 / (w * h);
    } else {
      s.set([0.5, 0.5, 0, 0, 1, 1, 0], k);
    }
    this.filled = Math.max(this.filled, i + 1);
  }

  meta() {
    const { id, name, provider, width, height, frames, params, filled } = this;
    return { id, name, provider, width, height, frames, params, filled };
  }
}

// ---------------------------------------------------------------- OPFS persistence
async function dir(videoKey) {
  const root = await navigator.storage.getDirectory();
  const masks = await root.getDirectoryHandle("masks", { create: true });
  return masks.getDirectoryHandle(videoKey.replace(/[^\w.-]+/g, "_").slice(0, 120), { create: true });
}

async function gzip(bytes) {
  const s = new Blob([bytes]).stream().pipeThrough(new CompressionStream("gzip"));
  return new Uint8Array(await new Response(s).arrayBuffer());
}
async function gunzip(blob) {
  const s = blob.stream().pipeThrough(new DecompressionStream("gzip"));
  return new Uint8Array(await new Response(s).arrayBuffer());
}

export async function saveTrack(videoKey, track) {
  try {
    // ask the browser not to evict our masks under storage pressure (Chrome may grant silently)
    if (navigator.storage?.persist && !(await navigator.storage.persisted())) await navigator.storage.persist().catch(() => {});
    const d = await dir(videoKey);
    const write = async (name, data) => { const f = await d.getFileHandle(name, { create: true }); const w = await f.createWritable(); await w.write(data); await w.close(); };
    await write(`${track.id}.bin.gz`, await gzip(track.data));
    await write(`${track.id}.stats`, track.stats);
    await write(`${track.id}.json`, JSON.stringify(track.meta()));
    return true;
  } catch (err) { console.warn("[masks] save failed", err); return false; }
}

export async function loadTracks(videoKey) {
  const out = [];
  try {
    const d = await dir(videoKey);
    for await (const [name, h] of d.entries()) {
      if (!name.endsWith(".json")) continue;
      try {
        const meta = JSON.parse(await (await h.getFile()).text());
        const t = new MaskTrack(meta);
        const bin = await gunzip(await (await d.getFileHandle(`${meta.id}.bin.gz`)).getFile());
        if (bin.length !== t.data.length) continue;
        t.data.set(bin);
        t.stats.set(new Float32Array(await (await (await d.getFileHandle(`${meta.id}.stats`)).getFile()).arrayBuffer()));
        t.filled = meta.filled ?? meta.frames;
        out.push(t);
      } catch (err) { console.warn("[masks] skip", name, err); }
    }
  } catch (err) { console.warn("[masks] load failed", err); }
  return out.sort((a, b) => a.id.localeCompare(b.id));
}

export async function deleteTrack(videoKey, id) {
  try {
    const d = await dir(videoKey);
    for (const n of [`${id}.bin.gz`, `${id}.stats`, `${id}.json`]) await d.removeEntry(n).catch(() => {});
  } catch (_) {}
}

export const videoKeyOf = (info) => `${info.name}_${info.size}_${info.lastModified}`;
