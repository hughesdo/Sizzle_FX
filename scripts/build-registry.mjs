// Scans public/effects/**/effect.json and writes public/effects/index.json.
// Drop a new effect folder in and it shows up in the library (the Vite plugin
// reruns this on file changes). Folders starting with "_" are skipped.

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
export const EFFECTS_DIR = path.join(ROOT, "public", "effects");

const DEFAULT_PASS = { name: "Image", file: "main.glsl", channels: { iChannel0: "input", iChannel1: "source" } };
const UNIFORM_TYPES = new Set(["float", "int", "bool", "enum", "color", "vec2", "text"]);

function walk(dir, out = []) {
  for (const ent of fs.readdirSync(dir, { withFileTypes: true })) {
    if (ent.name.startsWith("_") || ent.name.startsWith(".")) continue;
    const p = path.join(dir, ent.name);
    if (ent.isDirectory()) walk(p, out);
    else if (ent.name === "effect.json") out.push(p);
  }
  return out;
}

// Validate + normalise one effect.json. Returns {effect, errors}.
export function normaliseEffect(raw, relDir) {
  const errors = [];
  const e = { ...raw };
  if (!e.id) errors.push("missing id");
  if (!e.name) errors.push("missing name");
  e.category = e.category || "Misc";
  e.tags = Array.isArray(e.tags) ? e.tags : [];
  e.kind = e.kind || "filter";
  e.audio = !!e.audio;
  e.needsMask = !!e.needsMask;
  e.needsHistory = !!e.needsHistory;
  e.description = e.description || "";
  e.passes = Array.isArray(e.passes) && e.passes.length ? e.passes : [DEFAULT_PASS];
  e.passes = e.passes.map((p, i) => ({
    name: p.name || (i === e.passes.length - 1 ? "Image" : `Buffer${i}`),
    file: p.file,
    channels: p.channels || DEFAULT_PASS.channels,
  }));
  for (const p of e.passes) if (!p.file) errors.push(`pass ${p.name} has no file`);
  e.uniforms = e.uniforms || {};
  for (const [k, u] of Object.entries(e.uniforms)) {
    if (!UNIFORM_TYPES.has(u.type)) errors.push(`uniform ${k}: unknown type ${u.type}`);
    if (u.default === undefined) errors.push(`uniform ${k}: no default`);
  }
  e.path = relDir.split(path.sep).join("/");
  return { effect: e, errors };
}

export function buildRegistry({ quiet = false } = {}) {
  if (!fs.existsSync(EFFECTS_DIR)) fs.mkdirSync(EFFECTS_DIR, { recursive: true });
  const files = walk(EFFECTS_DIR);
  const effects = [];
  const seen = new Map();
  let bad = 0;
  for (const f of files) {
    const relDir = path.relative(path.join(ROOT, "public"), path.dirname(f));
    let raw;
    try { raw = JSON.parse(fs.readFileSync(f, "utf8")); }
    catch (err) { bad++; if (!quiet) console.warn(`[registry] bad JSON ${relDir}: ${err.message}`); continue; }
    const { effect, errors } = normaliseEffect(raw, relDir);
    for (const p of effect.passes) {
      if (p.file && !fs.existsSync(path.join(path.dirname(f), p.file))) errors.push(`missing file ${p.file}`);
    }
    if (seen.has(effect.id)) errors.push(`duplicate id (also in ${seen.get(effect.id)})`);
    if (errors.length) { bad++; if (!quiet) console.warn(`[registry] skip ${relDir}: ${errors.join("; ")}`); continue; }
    seen.set(effect.id, relDir);
    effects.push(effect);
  }
  effects.sort((a, b) => a.category.localeCompare(b.category) || a.name.localeCompare(b.name));
  const index = { version: 1, generated: new Date().toISOString(), count: effects.length, effects };
  fs.writeFileSync(path.join(EFFECTS_DIR, "index.json"), JSON.stringify(index, null, 1));
  if (!quiet) console.log(`[registry] ${effects.length} effects${bad ? `, ${bad} skipped` : ""}`);
  return index;
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) buildRegistry();
