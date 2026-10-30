// Imported from SuperTool effects/BitBlurry.glsl by scripts/import-supertool.mjs
// Bit Blurry Effect
// Wobble + variable separable-blur distortion extracted from the Generative
// shader "A bit blurry" (Shadertoy MflfR8 by mrange, CC0, 2024-08-11) and
// applied to the input video (iChannel0) instead of the original scene.
//
// Only the distortion logic is reused:
//   - hf()  : the animated radial height field that drives the wobble/blur
//   - the UV remap from Buffer C  : radial displacement of the sample coords
//   - the variable-radius separable blur from Buffer B/C : blur grows where the
//     height field is high (a = exp(-5*sf))
// NONE of the generative visuals are rendered (no raymarched plane-stack, no
// palette, no specular highlight) — the video frame is the only image source.
//
// The three "Bit Blurry Effect 1/2/3" library entries all point at THIS file;
// they differ only in their uniform defaults (amplitude / speed / blur / strength).

uniform float wobbleAmplitude;   // amplitude of the radial height-field wave
uniform float animSpeed;         // animation speed of the wobble
uniform float blurRadius;        // blur tap spacing (spread) in pixels
uniform float distortStrength;   // how strongly the wobble displaces the UVs

const float pi  = 3.14159265359;
const float tau = 6.28318530718;

// License: MIT, author: Inigo Quilez — smooth min (from the original Common).
float pmin(float a, float b, float k) {
  float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
  return mix(b, a, h) - k * h * (1.0 - h);
}
float pabs(float a, float k) { return -pmin(a, -a, k); }

// License: Unknown, author: Claude Brezinski — tanh approximation.
float tanh_approx(float x) {
  float x2 = x * x;
  return clamp(x * (27.0 + x2) / (27.0 + 9.0 * x2), -1.0, 1.0);
}

// Radial animated height field from "A bit blurry" (drives wobble + blur width).
float hf(vec2 p, float tm) {
  vec2 cp = vec2(0.0);
  float x = length(p - cp);
  const float rper = 6.0;
  const float wper = 1.0;
  const float xper = pi;
  float anim0 = smoothstep(-sqrt(0.5), sqrt(0.5), -cos(tm * tau / rper));
  float anim1 = smoothstep(-0.5, 0.5, -cos(0.5 * tm * tau / rper));
  float x0 = x;
  float x1 = x * xper;
  float ampl = 0.5 * tanh_approx(1.0 / (x0 * x0));
  float ang = pabs(x1, 1.0) - tau * tm / wper;
  float wave = cos(ang) * anim0;
  float h0 = ampl * (wave + anim0);
  float h1 = 1.0 - ampl * (-wave + anim0);
  return mix(h0, h1, anim1);
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
  vec2 res = iResolution.xy;
  vec2 q0 = fragCoord / res;

  // Aspect-correct symmetric coords, matching the original passes.
  vec2 p = -1.0 + 2.0 * q0;
  vec2 pp = p;
  p.x *= res.x / res.y;

  float tm = iTime * animSpeed;
  float sf = hf(p, tm) * wobbleAmplitude;

  // Wobble: radial UV displacement driven by the height field (Buffer C remap).
  vec2 q = 0.5 + 0.5 * (pp * (mix(1.0, 0.9 * tanh(0.5 + 0.5 * length(pp)),
                                  sf * distortStrength)));

  // Variable blur: falloff `a` shrinks (wider blur) where the field is high.
  float a = exp(-5.0 * sf);
  vec2 tsz = vec2(blurRadius) / res;

  // Single-pass 2D approximation of the original horizontal+vertical separable
  // blur: sample along both axes with the same exp(-a*i*i) weighting.
  vec3 col = texture(iChannel0, q).rgb;
  float agg = 1.0;
  for (float i = 1.0; i < 12.0; ++i) {
    float mul = exp(-a * i * i);
    vec2 off = tsz * i;
    col += mul * texture(iChannel0, q - vec2(off.x, 0.0)).rgb;
    col += mul * texture(iChannel0, q + vec2(off.x, 0.0)).rgb;
    col += mul * texture(iChannel0, q - vec2(0.0, off.y)).rgb;
    col += mul * texture(iChannel0, q + vec2(0.0, off.y)).rgb;
    agg += 4.0 * mul;
  }
  col /= agg;

  fragColor = vec4(col, 1.0);
}
