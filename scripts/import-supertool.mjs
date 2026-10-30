// Converts SuperTool's "Effects" shaders into Sizzle FX effect folders.
//   node scripts/import-supertool.mjs [path-to-SuperTool]
// Writes public/effects/supertool/<id>/{effect.json, *.glsl, assets/*}.
// Re-running overwrites those folders (hand edits belong in a copy outside supertool/).

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const ST = path.resolve(process.argv[2] || path.join(ROOT, "..", "SuperTool"));
const SHADERS = path.join(ST, "public", "shaders");
const OUT = path.join(ROOT, "public", "effects", "supertool");

const meta = JSON.parse(fs.readFileSync(path.join(SHADERS, "metadata.json"), "utf8"));

const has = (e, ...words) => {
  const hay = `${e.id} ${e.name} ${(e.tags || []).join(" ")}`.toLowerCase();
  return words.some((w) => hay.includes(w));
};

function classify(e) {
  if (has(e, "raymarch", "raytrac", "rayball", "dome", "cube", "tunnel", "echappatoire", "anastasia", "surf", "tvzoom", "tv-zoom", "amiga", "shaderwave", "electric")) return { category: "Scene", kind: "scene" };
  if (has(e, "overlay", "grid", "stripes", "dots", "checker", "hexagon", "voronoi", "plasma", "matrix-rain", "starfield", "triangles", "spiral", "rings", "interference", "pulsing-waves")) return { category: "Overlay", kind: "overlay" };
  if (has(e, "paint", "trails", "feedback")) return { category: "Feedback", kind: "filter" };
  if (has(e, "glitch", "vhs", "datamosh", "crt", "tiktok", "chromatic", "rgb")) return { category: "Glitch", kind: "filter" };
  if (has(e, "blur", "bitblurry")) return { category: "Blur", kind: "filter" };
  if (has(e, "shake", "wobble", "zoom", "twist", "vortex", "ripple", "wave", "barrel", "warp", "webby", "kaleido", "mirror", "heat", "liquid", "tilt", "dolly")) return { category: "Distort", kind: "filter" };
  if (has(e, "hue", "color", "candy", "posterize", "filters", "trippy", "drummer")) return { category: "Color", kind: "filter" };
  if (has(e, "bloom", "light", "ray", "flash", "strobe", "vignette", "beat", "particle", "sparkle")) return { category: "Light", kind: "filter" };
  if (has(e, "edge", "pixel", "mosaic", "skeleton")) return { category: "Stylize", kind: "filter" };
  return { category: "Misc", kind: "filter" };
}

function convertUniforms(u = {}) {
  const out = {};
  for (const [k, v] of Object.entries(u)) {
    const t = v.type === "text" ? "text" : v.type === "color" ? "color" : "float";
    out[k] = { type: t, default: v.default ?? (t === "float" ? 0 : t === "color" ? "#ffffff" : ""), label: k };
    if (t === "float") { out[k].min = v.min ?? 0; out[k].max = v.max ?? 1; out[k].step = v.step ?? 0.01; }
    if (v.description) out[k].description = v.description;
  }
  return out;
}

const warnings = [];

// Map one SuperTool channel binding to ours, copying any texture asset.
function convertChannel(ch, srcDir, dstDir, id) {
  if (ch == null) return undefined;
  if (typeof ch === "string") return ch === "video-input" ? "input" : ch;
  if (ch.type === "texture" && ch.file) {
    const src = path.resolve(srcDir, ch.file);
    if (!fs.existsSync(src)) { warnings.push(`${id}: missing asset ${ch.file}`); return "none"; }
    const name = path.basename(src);
    fs.mkdirSync(path.join(dstDir, "assets"), { recursive: true });
    fs.copyFileSync(src, path.join(dstDir, "assets", name));
    return { texture: `assets/${name}`, wrap: ch.wrap || "clamp", filter: ch.filter || "linear" };
  }
  warnings.push(`${id}: unsupported channel type ${ch.type} (bound to black)`);
  return "none";
}

function writeEffect(id, effect, files) {
  const dir = path.join(OUT, id);
  fs.mkdirSync(dir, { recursive: true });
  for (const [name, text] of Object.entries(files)) fs.writeFileSync(path.join(dir, name), text);
  fs.writeFileSync(path.join(dir, "effect.json"), JSON.stringify(effect, null, 2) + "\n");
}

fs.rmSync(OUT, { recursive: true, force: true });
fs.mkdirSync(OUT, { recursive: true });
let n = 0;

// ---- single-file effects
for (const e of meta.effects) {
  const id = `st-${e.id}`;
  const src = path.join(SHADERS, e.file);
  if (!fs.existsSync(src)) { warnings.push(`${id}: missing ${e.file}`); continue; }
  const dir = path.join(OUT, id);
  fs.mkdirSync(dir, { recursive: true });
  const channels = { iChannel0: "input" };
  for (const [k, ch] of Object.entries(e.channels || {})) channels[k] = convertChannel(ch, path.dirname(src), dir, id);
  const cls = classify(e);
  const glsl = `// Imported from SuperTool ${e.file} by scripts/import-supertool.mjs\n` + fs.readFileSync(src, "utf8");
  writeEffect(id, {
    id, name: e.name, category: cls.category, kind: cls.kind,
    description: e.description || `SuperTool: ${(e.tags || []).join(", ")}`,
    tags: [...(e.tags || []), "supertool"], audio: !!e.audioReactive,
    passes: [{ name: "Image", file: "main.glsl", channels }],
    uniforms: convertUniforms(e.uniforms),
  }, { "main.glsl": glsl });
  n++;
}

// ---- directory (multi-buffer) effects
for (const s of (meta.shaders || []).filter((x) => x.category === "effect")) {
  const srcDir = path.join(SHADERS, s.file || s.path || `effects/${s.id}`);
  const mf = path.join(srcDir, "meta.json");
  if (!fs.existsSync(mf)) { warnings.push(`${s.id}: no meta.json`); continue; }
  const m = JSON.parse(fs.readFileSync(mf, "utf8"));
  const id = `st-${s.id}`;
  const dir = path.join(OUT, id);
  fs.mkdirSync(dir, { recursive: true });
  const files = {};
  let passes;
  if (m.buffers) {
    const order = m.renderOrder || Object.keys(m.buffers);
    passes = order.map((name) => {
      const b = m.buffers[name];
      files[b.file] = `// Imported from SuperTool ${s.id}/${b.file}\n` + fs.readFileSync(path.join(srcDir, b.file), "utf8");
      const channels = {};
      for (const [k, ch] of Object.entries(b.channels || {})) channels[k] = convertChannel(ch, srcDir, dir, id);
      return { name, file: b.file, channels };
    });
  } else {
    const main = fs.existsSync(path.join(srcDir, "main.glsl")) ? "main.glsl" : "image.glsl";
    files["main.glsl"] = `// Imported from SuperTool ${s.id}/${main}\n` + fs.readFileSync(path.join(srcDir, main), "utf8");
    const channels = {};
    for (const [k, ch] of Object.entries(m.channels || {})) channels[k] = convertChannel(ch, srcDir, dir, id);
    if (!m.channels && m.inputMode && m.inputMode.startsWith("video")) channels.iChannel0 = "input";
    passes = [{ name: "Image", file: "main.glsl", channels }];
  }
  const cls = classify({ id: s.id, name: m.name || s.name, tags: m.tags });
  writeEffect(id, {
    id, name: m.name || s.name, category: cls.category, kind: cls.kind,
    description: m.description || (m.author ? `SuperTool · ${m.author}` : `SuperTool: ${(m.tags || []).join(", ")}`),
    tags: [...(m.tags || []), "supertool", "multipass"], audio: !!m.audioReactive,
    passes, uniforms: convertUniforms(m.uniforms),
  }, files);
  n++;
}

console.log(`[import-supertool] wrote ${n} effects to ${path.relative(ROOT, OUT)}`);
if (warnings.length) console.log(warnings.map((w) => "  ! " + w).join("\n"));
