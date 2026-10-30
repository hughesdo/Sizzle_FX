import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { normaliseEffect, buildRegistry, EFFECTS_DIR } from "../scripts/build-registry.mjs";

test("normaliseEffect fills defaults for a minimal effect", () => {
  const { effect, errors } = normaliseEffect({ id: "x", name: "X" }, "effects/x");
  assert.deepEqual(errors, []);
  assert.equal(effect.category, "Misc");
  assert.equal(effect.passes.length, 1);
  assert.equal(effect.passes[0].file, "main.glsl");
  assert.equal(effect.passes[0].channels.iChannel0, "input");
});

test("normaliseEffect rejects bad uniforms", () => {
  const { errors } = normaliseEffect({ id: "x", name: "X", uniforms: { a: { type: "mat4" }, b: { type: "float" } } }, "effects/x");
  assert.ok(errors.some((e) => e.includes("unknown type mat4")));
  assert.ok(errors.some((e) => e.includes("b: no default")));
});

test("registry builds, ids are unique, every pass file exists", () => {
  const idx = buildRegistry({ quiet: true });
  assert.ok(idx.count >= 100, `expected 100+ effects, got ${idx.count}`);
  const ids = new Set();
  for (const e of idx.effects) {
    assert.ok(!ids.has(e.id), `duplicate ${e.id}`); ids.add(e.id);
    for (const p of e.passes) assert.ok(fs.existsSync(path.join(EFFECTS_DIR, "..", e.path, p.file)), `${e.id}: ${p.file}`);
    for (const [k, u] of Object.entries(e.uniforms)) assert.notEqual(u.default, undefined, `${e.id}.${k} default`);
  }
});

test("multi-pass channels only reference real passes or built-ins", () => {
  const idx = JSON.parse(fs.readFileSync(path.join(EFFECTS_DIR, "index.json"), "utf8"));
  const builtins = new Set(["input", "source", "mask", "none"]);
  for (const e of idx.effects) {
    const names = new Set(e.passes.map((p) => p.name));
    for (const p of e.passes) for (const [ch, v] of Object.entries(p.channels || {})) {
      if (v && typeof v === "object") { assert.ok(v.texture, `${e.id}/${p.name}.${ch}`); continue; }
      assert.ok(builtins.has(v) || names.has(v), `${e.id}/${p.name}.${ch} -> ${v}`);
    }
  }
});
