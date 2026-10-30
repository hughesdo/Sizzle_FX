// Wraps an effect's Shadertoy-style source into a complete WebGL2 fragment shader.
// Every effect gets the same preamble (built-in uniforms, audio helpers, mask and
// history helpers), so effects stay small and the contract lives in ONE place.
// Phase 5's ModernGL renderer swaps "#version 300 es" for "#version 330 core".

export const TEX_UNITS = { iChannel0: 0, iChannel1: 1, iChannel2: 2, iChannel3: 3, iAudioFFT: 4, iMask: 5, iHistory: 6 };
export const HISTORY_DEPTH = 16;

export const VERTEX_SRC = `#version 300 es
void main(){
  vec2 p = vec2((gl_VertexID << 1) & 2, gl_VertexID & 2);
  gl_Position = vec4(p * 2.0 - 1.0, 0.0, 1.0);
}`;

const PREAMBLE = `#version 300 es
precision highp float;
precision highp int;
precision highp sampler2DArray;
uniform vec3  iResolution;
uniform float iTime;
uniform float iTimeDelta;
uniform int   iFrame;
uniform vec4  iMouse;
uniform vec4  iDate;
uniform float iProgress;
uniform float iSampleRate;
uniform vec3  iChannelResolution[4];
uniform sampler2D iChannel0;
uniform sampler2D iChannel1;
uniform sampler2D iChannel2;
uniform sampler2D iChannel3;
uniform sampler2D iAudioFFT;
uniform sampler2D iMask;
uniform sampler2DArray iHistory;
uniform int   iHistoryHead;
uniform int   iHistoryLen;
uniform float uBass, uLowMid, uMid, uHigh, uTreble, uLevel;
uniform float uKick, uSnare, uHat, uBeat, uBarPh, uFlow;
uniform float uAudio;
uniform float uReact;
uniform float uSegT, uSegTime, uSegDur, uMix, uSeed;
uniform float uHasMask;
uniform vec2  uMaskCentroid;
uniform vec4  uMaskBBox;
uniform float uMaskArea;
out vec4 fragColor;
#define HISTORY_DEPTH ${HISTORY_DEPTH}
`;

// SuperTool's helpers (same names + texture layout, so ported effects run as-is).
// Row v=0.25 is PCM, v=0.75 is the FFT. Results are scaled by the segment's
// audio-reactivity knob (uReact, default 1 = unchanged).
const HELPERS = `
float audioFreq(float hz){
  float u = clamp(hz / (iSampleRate * 0.5), 0.0, 1.0);
  return texture(iAudioFFT, vec2(u, 0.75)).x * uReact;
}
float audioWave(float u){ return texture(iAudioFFT, vec2(clamp(u, 0.0, 1.0), 0.25)).x; }
float audioBand(float loHz, float hiHz){
  float nyq = iSampleRate * 0.5;
  float lo = clamp(loHz / nyq, 0.0, 1.0), hi = clamp(hiHz / nyq, 0.0, 1.0);
  float s = 0.0;
  for (int i = 0; i < 16; i++){ float t = (float(i) + 0.5) / 16.0; s += texture(iAudioFFT, vec2(mix(lo, hi, t), 0.75)).x; }
  return s / 16.0 * uReact;
}
float audioRMS(){
  float s = 0.0;
  for (int i = 0; i < 32; i++){ float v = texture(iAudioFFT, vec2((float(i) + 0.5) / 32.0, 0.75)).x; s += v * v; }
  return sqrt(s / 32.0) * uReact;
}
float audioSmooth(float prev, float curr, float alpha){ return mix(curr, prev, alpha); }
float audioBeatEnergy(){ return smoothstep(0.55, 0.85, audioBand(20.0, 200.0)); }

// Mask (1.0 everywhere when no mask track is bound).
float maskAt(vec2 uv){ return uHasMask > 0.5 ? texture(iMask, uv).r : 1.0; }

// History ring: previous source frames (rgb) with their mask in alpha.
// framesAgo 0 = current frame. Clamped to what has actually been recorded.
vec4 historyTap(vec2 uv, int framesAgo){
  int n = max(iHistoryLen, 1);
  int f = clamp(framesAgo, 0, n - 1);
  int layer = (iHistoryHead - f + HISTORY_DEPTH * 4) % HISTORY_DEPTH;
  return texture(iHistory, vec3(uv, float(layer)));
}
`;

const BUILTIN_NAMES = "iResolution|iTime|iTimeDelta|iFrame|iMouse|iDate|iProgress|iSampleRate|iChannelResolution|iChannel[0-3]|iAudioFFT|iMask|iHistory|iHistoryHead|iHistoryLen|uBass|uLowMid|uMid|uHigh|uTreble|uLevel|uKick|uSnare|uHat|uBeat|uBarPh|uFlow|uAudio|uReact|uSegT|uSegTime|uSegDur|uMix|uSeed|uHasMask|uMaskCentroid|uMaskBBox|uMaskArea";

// Source clean-up rules, as data so the Python/ModernGL renderer (server/) applies
// exactly the same ones (scripts/export-contract.mjs writes them to server/contract.json).
// Each rule: replace `pattern` (flags) with `replace`; `when` = only if this pattern matches.
// Patterns stick to syntax that JS and Python `re` read the same way.
export const STRIP_RULES = [
  { pattern: "^[ \\t]*#version[^\\n]*", flags: "gm", replace: "" },
  // single-name declarations of anything the preamble owns
  { pattern: `uniform\\s+(?:(?:highp|mediump|lowp)\\s+)?\\w+\\s+(?:${BUILTIN_NAMES})\\s*(?:\\[\\s*\\d+\\s*\\])?\\s*;`, flags: "g", replace: "" },
  // legacy SuperTool scalar audio uniforms
  { pattern: "uniform\\s+(?:highp\\s+)?float\\s+iAudio(?:Bass|Mid|High|RMS|Beat)\\s*;", flags: "g", replace: "" },
  { pattern: "^\\s*out\\s+vec4\\s+fragColor\\s*;", flags: "m", replace: "" },
  // desktop GLSL 330 style from the old Python/ModernGL pipelines: "in vec2 fragCoord;"
  { id: "desktop", pattern: "^\\s*in\\s+vec2\\s+fragCoord\\s*;", flags: "m", replace: "" },
  { pattern: "^\\s*precision\\s+\\w+\\s+(?:float|int|sampler2D|sampler2DArray)\\s*;", flags: "gm", replace: "" },
];
// applied after the rules when the source used "in vec2 fragCoord;" (the "desktop" rule matched)
export const FRAGCOORD_RULE = { pattern: "\\bfragCoord\\b", flags: "g", replace: "gl_FragCoord.xy" };

function stripConflicts(src) {
  let s = src;
  const desktopRule = STRIP_RULES.find((r) => r.id === "desktop");
  const desktop = new RegExp(desktopRule.pattern, "m").test(s);
  for (const r of STRIP_RULES) s = s.replace(new RegExp(r.pattern, r.flags), r.replace);
  if (desktop) s = s.replace(new RegExp(FRAGCOORD_RULE.pattern, FRAGCOORD_RULE.flags), FRAGCOORD_RULE.replace);
  return s;
}

export const MAIN_IMAGE_RE = "void\\s+mainImage\\s*\\(";
export const MAIN_RE = "void\\s+main\\s*\\(\\s*(?:void)?\\s*\\)";
export const MAIN_WRAPPER = "void main(){ mainImage(fragColor, gl_FragCoord.xy); }\n";

// target "webgl2" (browser) or "gl330" (server ModernGL); only the version line differs.
export function buildFragment(source, target = "webgl2") {
  const body = stripConflicts(source);
  const hasMainImage = new RegExp(MAIN_IMAGE_RE).test(body);
  const hasMain = new RegExp(MAIN_RE).test(body);
  const pre = target === "gl330" ? PREAMBLE.replace("#version 300 es", "#version 330 core") : PREAMBLE;
  let out = pre + HELPERS + "\n#line 1\n" + body + "\n";
  if (hasMainImage && !hasMain) out += MAIN_WRAPPER;
  return out;
}

export const CONTRACT = { PREAMBLE, HELPERS, VERTEX_SRC, TEX_UNITS, HISTORY_DEPTH };

// Number of lines before user code, for mapping compile errors back to the effect file.
export const USER_LINE_OFFSET = 0; // "#line 1" resets numbering at the user source
