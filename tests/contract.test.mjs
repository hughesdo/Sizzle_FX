import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import { CONTRACT, STRIP_RULES, buildFragment } from "../src/render/glslLoader.js";

// server/contract.json is generated from glslLoader.js; if they drift, the Python
// renderer would wrap effects differently from the browser.
test("server/contract.json matches src/render/glslLoader.js", () => {
  const c = JSON.parse(fs.readFileSync(new URL("../server/contract.json", import.meta.url), "utf8"));
  assert.equal(c.preamble, CONTRACT.PREAMBLE.replace("#version 300 es", "#version 330 core"), "preamble drifted: run npm run contract");
  assert.equal(c.helpers, CONTRACT.HELPERS, "helpers drifted: run npm run contract");
  assert.deepEqual(c.stripRules, STRIP_RULES, "strip rules drifted: run npm run contract");
  assert.equal(c.sample.expected, buildFragment(c.sample.source, "gl330"));
});

test("gl330 target only changes the version line", () => {
  const src = "uniform float a;\nvoid mainImage(out vec4 o, in vec2 c){ o = vec4(a); }\n";
  const es = buildFragment(src), core = buildFragment(src, "gl330");
  assert.ok(es.startsWith("#version 300 es") && core.startsWith("#version 330 core"));
  assert.equal(es.replace("#version 300 es", ""), core.replace("#version 330 core", ""));
});
