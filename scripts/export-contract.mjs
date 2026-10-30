// Writes server/contract.json from src/render/glslLoader.js so the Python/ModernGL
// renderer wraps effects with exactly the same preamble, helpers and clean-up rules.
// Run automatically by server/start (and `npm run contract`).
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { CONTRACT, STRIP_RULES, FRAGCOORD_RULE, MAIN_IMAGE_RE, MAIN_RE, MAIN_WRAPPER, buildFragment } from "../src/render/glslLoader.js";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const out = {
  generatedFrom: "src/render/glslLoader.js",
  vertex: CONTRACT.VERTEX_SRC.replace("#version 300 es", "#version 330 core"),
  preamble: CONTRACT.PREAMBLE.replace("#version 300 es", "#version 330 core"),
  helpers: CONTRACT.HELPERS,
  texUnits: CONTRACT.TEX_UNITS,
  historyDepth: CONTRACT.HISTORY_DEPTH,
  stripRules: STRIP_RULES,
  fragCoordRule: FRAGCOORD_RULE,
  mainImageRe: MAIN_IMAGE_RE,
  mainRe: MAIN_RE,
  mainWrapper: MAIN_WRAPPER,
  // golden sample so the Python port can self-check its rule handling
  sample: { source: "#version 300 es\nuniform vec3 iResolution;\nin vec2 fragCoord;\nout vec4 fragColor;\nvoid mainImage(out vec4 o, in vec2 c){ o = vec4(fragCoord, 0.0, 1.0); }\n" },
};
out.sample.expected = buildFragment(out.sample.source, "gl330");
fs.writeFileSync(path.join(ROOT, "server", "contract.json"), JSON.stringify(out, null, 1));
console.log("[contract] wrote server/contract.json");
