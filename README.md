# Sizzle FX

**Try it in your browser: https://hughesdo.github.io/Sizzle_FX/** (Chrome or Edge, desktop)

**Watch the 3-minute walkthrough: https://youtu.be/RPePpgD1chE** (also built in: the editor's **? help** button).

GPU shader-effects editor for video. Drop a video, drag effects onto a multi-lane
timeline, tune each segment, preview live, export an MP4 for X / YouTube.

- 133 effects (95 imported from SuperTool, 38 originals incl. 11 person-mask "Body" effects), audio-reactive to the video's own soundtrack
- Subject masks baked on your GPU: green-screen key, auto person (RVM), click-to-select (SAM 2). Any effect can be scoped to the subject or the background
- Real effect stacking: each lane feeds the next
- Export: H.264 High, constant-quality, BT.709, fast start; source AAC copied untouched
  (other audio re-encoded to AAC-LC)
- Everything runs in the browser on your GPU (Chrome/Edge). Optional Python render server
  (`server/`, ModernGL + ffmpeg/NVENC) renders the same effects for x264 quality or long jobs.

## Run

```
npm install
npm run dev
```

Open http://localhost:5180 (or double-click `start.bat`). Mask models: `npm run fetch-models`.

Server rendering (optional): `server\start.bat` (first run builds a Python 3.11 venv), then pick
"server gpu (python)" in the header's render menu.

## Web version vs desktop install

The web version (GitHub Pages, rebuilt by `.github/workflows/pages.yml` on every push to main) has the
whole editor: all effects, audio reactivity, person masks and click-to-select, and browser MP4 export.
Everything runs on your own GPU; your video never leaves your computer.

The desktop install (`npm install` + `npm run dev`, plus `server\start.bat`) adds what needs the local
Python server: the named project library below and server rendering (x264 / NVENC). On the web,
**save .json** downloads the timeline instead. Mask baking is also faster locally: GitHub Pages can't
enable the browser's multithreading, so the wasm fallback runs single-threaded there.

Build the web version yourself: `SFX_BASE=/Sizzle_FX/ VITE_HOSTED=1 npm run build`.

## Projects

**projects** in the header saves, opens and deletes named projects (ctrl+s saves, ctrl+shift+s saves as).
Each one is a folder in `Documents\Sizzle FX\Projects\<name>\`: `project.sfx.json` (the timeline,
plain JSON you can edit and re-open; the previous save is kept as `.bak`) plus its baked masks. The
source video is copied once into `Documents\Sizzle FX\Media\`, so a project reopens with its video,
masks and effects. This uses the local server (`server\start.bat`); set `SIZZLEFX_HOME` to move the library.

## Help

The **? help** button in the editor opens `public/help.html`: a 3-minute narrated walkthrough
(chapters for every feature, same video as https://youtu.be/RPePpgD1chE) and a written guide. The walkthrough is rebuilt from `demo/`.

## Add effects

See [docs/EFFECTS.md](docs/EFFECTS.md). Drop a folder in `public/effects/` and it appears in the library.
Re-import SuperTool's effects with `npm run import-supertool`.

## Test

- `npm test` registry + audio analysis
- http://localhost:5180/tools/compile-all.html compiles and renders every effect
- `tools/e2e.js` in-page end-to-end export test (see the header comment)
