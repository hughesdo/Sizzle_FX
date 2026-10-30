# Writing a Sizzle FX effect

An effect is a folder. Drop it anywhere under `public/effects/` and it appears in the
library (the dev server rebuilds `public/effects/index.json` and reloads the library).
Folders starting with `_` are ignored, so `_drafts/` is a safe place for work in progress.

```
public/effects/core/my-effect/
  effect.json
  main.glsl
  (more .glsl passes, assets/*.png)
```

## effect.json

```json
{
  "id": "my-effect",                 // unique across the whole library
  "name": "My Effect",
  "category": "Glitch",              // Body Glitch Color Look Blur Distort Temporal Light Stylize Overlay Scene Keying Feedback
  "description": "One sentence shown in the library and the segment panel.",
  "tags": ["rgb", "split"],
  "kind": "filter",                  // filter | overlay | scene (badge only)
  "audio": true,                     // shows the ♪ badge
  "needsMask": false,                // uses maskAt()/iMask (◐ badge)
  "needsHistory": false,             // uses historyTap() (⧗ badge)
  "uniforms": {
    "amount": { "type": "float", "default": 0.5, "min": 0, "max": 1, "step": 0.01, "label": "amount", "description": "tooltip" },
    "count":  { "type": "int",   "default": 4, "min": 1, "max": 16 },
    "on":     { "type": "bool",  "default": 1 },
    "mode":   { "type": "enum",  "options": ["add", "screen"], "default": 0 },
    "tint":   { "type": "color", "default": "#ff00ff" },
    "center": { "type": "vec2",  "default": [0.5, 0.5], "min": 0, "max": 1 }
  }
}
```

Declare each uniform in GLSL with the matching type (`uniform float amount;`, `uniform int mode;`,
`uniform vec3 tint;`, `uniform vec2 center;`). bool/enum can be `int` or `float`; the renderer
reads the GL type and sets it correctly. Unset uniforms always get their `default` (never 0).

## main.glsl

Shadertoy style. Do NOT declare the built-ins below; the loader adds them.

```glsl
uniform float amount;
void mainImage(out vec4 fragColor, in vec2 fragCoord){
  vec2 uv = fragCoord / iResolution.xy;
  vec3 c = texture(iChannel0, uv).rgb;          // chain input (effects below this lane)
  fragColor = vec4(mix(c, 1.0 - c, amount * uAudio), 1.0);
}
```

### Built-ins

| name | meaning |
|---|---|
| `iChannel0` | chain input (the video after every lane below) |
| `iChannel1` | original source frame |
| `iResolution` `iTime` `iTimeDelta` `iFrame` | Shadertoy meaning. iTime = video time. iFrame = frames since segment start (multi-pass: since buffers started) |
| `iAudioFFT` `iSampleRate` | SuperTool 512x2 audio texture (row v=0.25 PCM, v=0.75 FFT) |
| `audioBand(lo,hi)` `audioFreq(hz)` `audioRMS()` `audioWave(u)` `audioBeatEnergy()` | SuperTool helpers |
| `uBass uLowMid uMid uHigh uTreble uLevel` | song-normalised bands, 0..1, smoothed |
| `uKick uSnare uHat` | hit envelopes: jump on a hit, decay |
| `uBeat uBarPh` | 0..1 phase through the current beat / bar |
| `uFlow` | time that runs faster when the music is loud (great for animation speed) |
| `uAudio` | **the segment's chosen "audio drive"** (level/bass/kick...). Prefer this for your main reaction |
| `uReact` | segment audio-reactivity knob (already applied to the values above) |
| `uSegT` `uSegTime` `uSegDur` `uMix` `uSeed` | segment progress 0..1, seconds in, length, fade-shaped mix, seed |
| `maskAt(uv)` `uHasMask` `iMask` | the segment's mask track (1.0 everywhere when the video has no mask) |
| `uMaskCentroid` `uMaskBBox` `uMaskArea` | per-frame subject centre / box (x0,y0,x1,y1) / coverage, uv space, origin bottom-left |
| `historyTap(uv, framesAgo)` | previous SOURCE frames (0 = now, up to 15), rgb + mask in alpha |

Pixel sizes: write them "at 1080p" and scale by `iResolution.y / 1080.0` so preview (maybe half res)
and export look identical.

## Masks (Body effects)

Set `"needsMask": true`. `maskAt(uv)` is 0..1 (subject = 1). The pattern for "copies of
the person": transform `uv` around `uMaskCentroid`, sample `iChannel0` and `maskAt` at the
transformed point, accumulate, then put the live subject back on top with
`mix(result, base, maskAt(uv))`. `historyTap(uv, k).a` is the mask k frames ago, which gives
silhouette trails for free. Any effect can also be limited to subject/background without
code: that is the segment's Scope setting.

## Multi-pass / feedback

```json
"passes": [
  { "name": "Trail", "file": "trail.glsl", "channels": { "iChannel0": "input", "iChannel1": "Trail" } },
  { "name": "Image", "file": "main.glsl",  "channels": { "iChannel0": "input", "iChannel1": "Trail" } }
]
```

Channel values: `input`, `source`, `mask`, `none`, another pass name, or `{ "texture": "assets/x.png", "wrap": "repeat" }`.
Reading a pass that already ran this frame gives this frame's result; reading itself (or a later pass)
gives last frame's. The LAST pass is the effect output. Seed buffers when `iFrame == 0`.
Every segment gets its own buffers, so the same effect can be on the timeline twice.

## Check your work

1. `npm run dev`, open http://localhost:5180/tools/compile-all.html, look for your id in the JSON.
2. In the app, drop it on a lane, open the panel, move every slider.
3. `npm test` validates the registry.

## GLSL gotchas (Chrome on Windows runs WebGL through ANGLE/D3D)

- `pow(0.0, y)` can return NaN there, and one NaN in a sum blacks out the whole effect (compile-all
  still says "rendered"). Write `(1.0 - t) * (1.0 - t)` or `pow(max(x, 1e-6), y)` instead.
- Don't name a uniform after a GLSL built-in (`length`, `step`, `mix`, `distance`...).
- Check a new effect on real footage too (the audition sheet in demo2/tools/audition.js, or the app),
  not just compile-all's test pattern.
