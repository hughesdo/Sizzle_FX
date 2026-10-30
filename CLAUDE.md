# CLAUDE.md :: Sizzle FX

Read this whole file before doing anything. It is the source of truth. Update it at
the end of every working session (see "Session ritual").

Owner: Don (@OneHung). Windows, GTX 1080 Ti. Prefers direct honest communication,
no em dashes, complete working files over partial diffs, CLI/batch workflows.

## What this is

Sibling of Sizzle. User uploads a VIDEO, drags shader effects onto a multi-lane
timeline, sizes segments, clicks a segment to tune its uniforms in a side panel,
watches a live GPU preview, exports an MP4 that X/YouTube accept. Audio-reactive
effects listen to the video's own audio. The effects library grows by dropping
folders into `public/effects/` (no app changes).

## Locked decisions (2026-10-29, grilled with Don)

| Topic | Decision |
|---|---|
| Codebase | New vanilla JS (ES modules + Vite, no framework). NOT a SuperTool fork |
| Renderer | WebGL2, ONE context, RGBA16F ping-pong, real chaining, per-segment feedback state |
| Export v1 | Browser: Mediabunny decode -> same renderer -> WebCodecs H.264 High -> MP4 fastStart |
| Audio out | Copy source AAC-LC packets untouched; anything else re-encoded to AAC-LC 192k. Never Opus-in-MP4 |
| Server render | Phase 5: Python + ModernGL + ffmpeg running the SAME effect files. Toggle already in the header |
| Masking | v1 scope includes BOTH RVM (auto people) and SAM2 (click to select), baked into mask tracks |
| Scope | Every segment: Whole / Subject / Background (+ feather, choke). Compositor does it generically |
| Timeline | Multi-lane, bottom lane renders first, each lane above feeds on it |
| Audio analysis | Offline, once per video (Timewarp analysis.js port). Preview and export read the same data |

## Architecture (where things live)

- `src/render/glslLoader.js` the effect contract: preamble uniforms, SuperTool audio helpers,
  `maskAt()`, `historyTap()`, texture unit map. Change the contract HERE only.
- `src/render/renderer.js` the ONE frame builder. `render(frame)` = source -> lanes -> scope composite -> canvas.
  History ring (16 frames, half res, rgb=source, a=mask). Multi-pass effects get their own iFrame counter that resets on seek.
- `src/project.js` project model + `buildFrame()` (shared by preview and export). Autosave in localStorage.
- `src/audio/analysis.js` (+ `.worker.js`) bands, kick/snare/hat envelopes, beats, uFlow, peaks, and
  SuperTool-layout 512x2 iAudioFFT rows at 100 Hz.
- `src/media/source.js` probe (fps from PTS span, snapped), mono audio decode, timeline thumbnails.
- `src/media/export.js` export pipeline + presets + avc level picker.
- `src/timeline/timeline.js` multi-lane timeline (ported from Sizzle static/app.js).
- `src/ui/segmentModal.js` side panel, controls generated from effect.json.
- `src/ui/library.js`, `src/ui/renderMode.js` (capability detection).
- `scripts/build-registry.mjs` scans effects -> `public/effects/index.json` (Vite plugin reruns on change + live reload).
- `scripts/import-supertool.mjs` regenerates `public/effects/supertool/` from `../SuperTool`.
- `tools/compile-all.html` compiles + renders every effect (open in browser, read the JSON).
- `tools/e2e.js` in-page end-to-end test (open clip, stack effects, export, save via `/__dev/save`).
- `docs/EFFECTS.md` how to write an effect. Read it before adding effects.

## Effect format

`public/effects/<group>/<id>/effect.json` + `main.glsl` (+ more passes). Shadertoy `mainImage`.
iChannel0 = chain input, iChannel1 = original source. Uniform types: float, int, bool, enum, color, vec2, text.
Full spec in `docs/EFFECTS.md`.

## Status

- [x] Phase 0 scaffold: Vite app, CLAUDE.md, docs/EFFECTS.md, start.bat, tests
- [x] Phase 1 core: open video + probe, audio analysis worker, multi-lane timeline (thumbs, waveform, beats,
      snap/magnet, drag between lanes, trim both edges), library, auto-generated segment panel, WebGL2 chain,
      scope composite (waits on masks), history ring, multi-pass + texture-asset channels, live preview
- [x] Phase 2 export: H.264 High + quantizer (CRF-like) w/ bitrate fallback, BT.709 tags, CFR timestamps,
      AAC copy / re-encode, fastStart, cancel, progress, timeline lock while rendering
- [x] Phase 3 library: 95 SuperTool effects imported + 34 originals = 129. `core/` adds the full Timewarp
      post.glsl split (curved screen, smear, mirror echo, light bars, lens flare w/ follow-subject, lightning),
      slit-scan (15-frame history), thermal (mask = hot subject), bleach bypass, halation, chroma key with
      despill + backgrounds. Library cards show live thumbnails rendered from the user's own video
      (`src/ui/thumbs.js`, second small WebGL renderer, ~4.5 s for 129 effects, refreshed when the video,
      audio analysis, registry or finished masks change)
- [x] Phase 4 masking: three providers baked into mask tracks (◐ masks button under the preview):
      green-screen key (CPU), RVM auto person (WebGPU), SAM 2.1 tiny click-to-select with whole/part/detail
      + tracking. Per-segment Scope (whole/subject/background, feather, choke, which mask), iMask, per-frame
      centroid/bbox/area, history alpha = mask, mask check overlay. 9 Body effects in `public/effects/body/`:
      Rotational Clone, RGB Split Clone, Silhouette Echo, Neon Outline, Subject Aura, Background Swap,
      Spotlight, Subject Afterimage, Pulse Clone. (Beat Clone Stamp dropped: needs > 16 frames of history.)
- [x] Phase 5 server render: `server/` FastAPI + ModernGL + ffmpeg runs the SAME effect files; header
      "render" toggle offers "server gpu (python)" when /api/status answers (Vite proxies /api -> :8790).

## Server render notes (read before touching server/)

- `server/start.bat` (or `npm run server`): creates `server/.venv` (Python 3.11; pip needs
  `--use-feature=truststore` on this PC because Avast intercepts TLS), regenerates the contract, runs uvicorn on
  127.0.0.1:8790. The root `start.bat` launches it too when the venv exists. In production `app.py` also
  serves `dist/`.
- Single source of truth: `src/render/glslLoader.js`. `scripts/export-contract.mjs` -> `server/contract.json`
  (preamble/helpers/strip rules as data); `server/contract.py` self-checks against a golden sample at import,
  and `tests/contract.test.mjs` fails if contract.json is stale. Never hand-edit contract.json.
- `server/renderer.py` is a line-for-line port of renderer.js (`frames.py` ports buildFrame/sampleAnalysis).
  ModernGL can't attach one layer of a texture array, so history layers are written via a half-res readback.
  Images travel bottom-up: ffmpeg `vflip` on decode and encode.
- The browser sends: video, project, its analysis (+ iAudioFFT rows as binary) and finished mask tracks
  (gzip R8 + stats). So server == preview without re-running analysis or RVM/SAM in Python.
- Encode: NVENC (`p7`, cq 19/16) when it works, else libx264 crf 18/15 preset slow/slower; `h264_metadata`
  bitstream filter writes the BT.709 VUI (NVENC ignored -color_primaries/-color_trc otherwise).
  AAC-LC copied, other audio -> AAC-LC 192k. Decode matrix: tagged sources use their tag, untagged = BT.709.
- Jobs: single-lane queue on a worker thread, GL context per job, cancel via DELETE /api/jobs/{id},
  work dirs in `server/_work/` (cleaned after 6 h). `server/compile_all.py` = GLSL 330 compile-all.
- uvicorn runs without --reload: restart it after editing server/*.py (kill the process on :8790).

## Masking notes (read before touching src/mask/)

- Files: `src/mask/maskTrack.js` (R8 frames + stats, OPFS gzip persistence), `masks.js` (manager),
  `bake.worker.js` (all three providers), `ort.js` (ONNX Runtime loader + model list), `src/ui/maskPanel.js`.
- Storage changed from the plan's "H.264 mask video" to gzipped 8-bit frames in OPFS: lossless, simpler,
  and black/white masks compress hard. Mask size: long side 640, multiples of 32, shrunk to fit 600 MB RAM.
- Models live in `public/models/` (gitignored). `npm run fetch-models` downloads them (~170 MB).
  For a hosted build, self-host them under /models/ (GitHub release assets may not allow browser CORS).
- ONNX Runtime 1.24.1: use the JSEP WebGPU backend (`ort.all.bundle.min.mjs`). The newer native WebGPU EP
  (`ort.webgpu` bundle) fails on RVM's first run with "Buffer used in submit while destroyed".
  JSEP can't do AveragePool(ceil_mode=1), so `ort.js` patches RVM's 3 ceil_mode attributes to 0 in the
  model bytes; exact because mask sizes are multiples of 32 and downsample is 0.5 (all pools see even sizes).
- ORT runtime files are copied to `public/ort/` when vite.config.js loads. Vite only indexes public/ at
  startup: after changing that list, fully restart the dev server (kill the node process on :5180).
- Timings on the 1080 Ti, 143-frame 720p clip: key 2.4 s, RVM ~11 s incl. model load (~40 ms/frame),
  SAM 2 ~55 s (encode ~260 ms/frame, GPU prompt decode ~50 ms; the CPU decoder was ~350 ms).
- SAM 2 picking: its 3 readings' IoU scores differ a lot between GPU and CPU decoders and max-IoU picks
  just the face for a face click, so selection ranks by AREA (whole/part/detail buttons). Tracking re-prompts
  each frame with last mask's box + centroid point + background box corners, picks the reading with the best
  mask-IoU vs last frame, clips to a grown box, clears edge bars, and holds last frame if overlap < 0.45.
  Measured vs RVM (mean IoU over 143 frames): this = 0.83 (0.95-0.99 up to frame 70, weaker on the fastest
  arm swings at the frame edge). Worse variants tried: hold capped at 2 frames / no hold (collapse to 0
  ~frame 115), grid of background negatives + no box when box > 60% of frame (0.64). For people use RVM.
- Edge bars: letterbox/pillarbox strips get keyed/segmented as subject (SAM glues them to a dark jacket).
  `clearEdgeBars` drops near-full columns/rows at the frame edge for every provider.
- Key vs RVM agree at mean IoU 0.968 on the green-screen clip (the key is ground truth there).

## Demo video + help page (2026-10-30)

- In-app help: header "? help" -> `public/help.html` (chapters seek the video; `#t=SECONDS` deep links)
  with `public/help/sizzle_fx_walkthrough.mp4` (web copy, x264 crf 24, ~40 MB) + `poster.jpg`.
- Walkthrough pipeline in `demo/` (adapted from Downloads/Shaders/RouletteVideo): `scenes.json` narration
  (edge-tts en-US-AndrewNeural via `tools/narration.py`), `tools/shoot.py` drives a separate full-screen
  Chrome (`py tools/cdp.py launch`, port 9333, profile in demo/chrome-profile) per scene with ddagrab capture,
  `tools/build.py` assembles (sped-up bakes with "Nx" tag, clip audio re-synced from play marks, ducking,
  -14 LUFS). Master: `demo/out/sizzle_fx_walkthrough.mp4` (1080p30, 2:58). Demo clip:
  `demo/assets/fx_demo_clip.mp4` = Downloads\64ee381c5ac3_VIDEO2.mp4 from 1:58, 23 s.
- Re-shoot order matters (state carries over): s02..s09 in one run; `s09_export` saves the server render to
  test-media/_out/demo_result.mp4, which s01/s10/s11 use.
- Gotchas: click the file input only with `Page.setInterceptFileChooserDialog` on (else the native
  Windows dialog covers the app and shows the PC's folders); CDP drag interception drops our custom
  `text/x-effect` type, so drops are synthetic DragEvents with a real cursor glide; Vite must ignore
  demo/** (the recording profile's locked files crashed the watcher with EBUSY); scale+crop+setsar=1 for
  non-16:9 footage (SAR 45:44 made players stretch to 1964 px).

## Verified (2026-10-29/30)

- Phase 5: server compile-all 129/129 (GLSL 330). Same masked/scoped/body-effect project exported both ways:
  server NVENC vs browser PSNR mean 45.3 dB (min 40.7), server x264 vs browser 44.5 dB: same picture.
  Server files: h264 High, bt709 primaries/transfer/matrix, tv range, 143/143 frames, AAC-LC copied
  (Opus source -> AAC-LC re-encoded), moov before mdat. Cancel mid-render stops the job.
  Speed, 143 frames: 720p server ~2.6-3.8 s incl. upload; 1440p server 5.4 s vs browser 1.4 s
  (browser path is faster on this GPU; the server is there for x264 quality, long jobs, weak browsers).
- `npm test`: 12/12 (adds contract drift test)

- compile-all: 129/129 effects compile and render (after Phase 3 finish); contact sheet of the 11 new
  effects on the Rave clip checked visually
- compile-all: 118/118 effects compile and render (after Phase 4)
- masks: key / RVM / SAM2 baked on Rave_starlight4, restored from OPFS after reload; export with Scope
  (RGB split on subject only, kaleidoscope on background only) + Rotational Clone + Silhouette Echo:
  143/143 frames, h264 High, bt709, AAC LC copied; frames checked visually
- compile-all: 109/109 effects compile and render non-black on the test pattern (Phase 2)
- e2e on Rave_starlight4 (720p24, AAC-LC): 4 stacked effects, export 143/143 frames, ffprobe = h264 High,
  yuv420p, bt709 x3, tv range, 24/1, AAC LC 48k stereo copied, moov before mdat, durations identical to source
- e2e on Opus-in-MKV variant: audio re-encoded to AAC LC, fps detected 24 (was 23.81 before PTS-span fix)
- preview vs export pixel check: PSNR ~43.5 dB at frames 48 and 100 (difference = H.264 compression only)
- `npm test`: 10/10 (registry, audio analysis, fps snap, mask size/stats)

## Known gaps / gotchas

- In the Claude desktop Browser pane the page can run as a background tab: rAF stalls, so `requestDraw`
  falls back to setTimeout when `document.hidden`. Headless `--dump-dom` fires before async work; use the pane + JS.
- Preview after a seek: history-based effects need a few frames to refill (export is always sequential, so exact).
- Feedback effects re-run when you tweak a slider while paused (state advances); harmless.
- Export holds the whole MP4 in memory (BufferTarget). Long 4K exports: switch to StreamTarget + showSaveFilePicker.
- st-vagas-dome needs a video channel (unsupported, bound to black).
- Rotated phone videos: export uses CanvasSink (applies rotation); not yet tested with a rotated file.
- Masks live in OPFS, which the browser may evict (the Claude Browser pane wiped them between sessions).
  saveTrack asks for `navigator.storage.persist()`; if a mask vanishes, re-bake. Exporting masks with the
  project file is a possible follow-up.
- Tooling gotcha: ffmpeg `xstack` on canvas JPEGs (yuvj) crashed with heap corruption (0xC0000374, bash
  shows exit 127). Put `format=yuv420p` before `scale` in contact-sheet filters.

## Open decisions

- GitHub repo: https://github.com/hughesdo/Sizzle_FX (PRIVATE, Don's choice: the help video uses VIDEO2
  footage). Ask Don before making it public.
- Hosting target for the static build (GitHub Pages / Cloudflare Pages); WebGPU for RVM/SAM2 needs HTTPS.
- Keyframed uniforms vs per-segment static values (static for now).

## Future TODO

MatAnyone2 as a server matte provider, keyframed uniforms, transitions, green-screen background layer,
optical-flow effects (datamosh, molten advection), per-effect presets, StreamTarget export for long videos.

## Session ritual

START: read this file. Check Status + Open decisions. `npm run dev` (or start.bat), open http://localhost:5180
WORK:  complete files; new effects go in their own folder; run tools/compile-all.html after shader work.
END:   update Status checkboxes, Verified, Open decisions; add a dated line to the Progress log.

## Progress log

- 2026-10-29 Planned with Don (decisions above). Built Phases 0-2 and bootstrapped Phase 3: vanilla Vite app,
  WebGL2 chain renderer, Timewarp audio analysis port with SuperTool-compatible FFT rows, Sizzle timeline port
  extended to lanes, generated segment panel, SuperTool importer (95 effects), 14 original effects, browser
  export verified with ffprobe + PSNR. Next: finish Phase 3 effects, then Phase 4 masking (RVM first).
- 2026-10-29 Phase 4 masking done: key + RVM + SAM 2.1 tiny bake in a worker on WebGPU (ORT JSEP, RVM
  ceil_mode patch), mask tracks in OPFS, Scope on every segment, multi-mask renderer, mask overlay, 9 Body
  effects. SAM tracking tuned over 5 measured variants (0.83 mean IoU vs RVM). Next: rest of Phase 3
  effects + library thumbnails, then Phase 5 server render.
- 2026-10-30 Phase 3 finished: 11 more originals (Timewarp split, slit-scan, thermal, bleach bypass,
  halation, chroma key), live library thumbnails from the user's video, storage.persist for masks.
  129 effects, all compile. Next: Phase 5 server render (FastAPI + ModernGL + ffmpeg).
- 2026-10-30 Phase 5 done: Python render server (ModernGL port of the renderer, shared contract generated
  from glslLoader.js, ffmpeg pipes, NVENC/x264, job queue), browser upload/poll/download, render toggle on.
  All phases complete. Next (Don's request): narrated demo video driving the app (hard features: masks,
  SAM 2 select, Scope, Body effects, lanes, both export paths) using test clips +
  Downloads\64ee381c5ac3_VIDEO2.mp4, then publish it + a written guide as an in-site help page.
- 2026-10-30 Narrated walkthrough recorded by driving the app (open, drag/tune, lanes, RVM mask, scope,
  body effects, SAM 2 select + track, browser + server export, result) and published as the in-app help
  page with a 14-section written guide. Nothing committed yet; GitHub repo still waiting on Don.
- 2026-10-30 git init + first commit (334 files, ~50 MB incl. the 40 MB help video). Ignored: regenerable
  demo clip + narration WAVs. Secret/personal-path scan clean. Pushed to private repo hughesdo/Sizzle_FX.
