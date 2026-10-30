// End-to-end smoke test, run inside the app page:
//   const t = await import('/tools/e2e.js'); await t.run({ clip: 'Rave_starlight4.mp4', export: true })
// Opens a clip from test-media/, places a stack of effects, checks preview frames,
// optionally exports and saves the MP4 to test-media/_out/ (dev server endpoint).

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
async function until(fn, ms = 30000) { const t0 = performance.now(); while (!fn()) { if (performance.now() - t0 > ms) return false; await sleep(100); } return true; }

export async function open(clip) {
  const app = window.__sfx;
  await until(() => app.effects.size > 0);
  const b = await (await fetch(`/test-media/${clip}`)).blob();
  localStorage.clear();
  await app.openVideo(new File([b], clip, { type: b.type, lastModified: 1 }));
  if (app.info.audio) await until(() => app.analysis);
  return app;
}

export async function seek(t) {
  const v = document.querySelector("#video");
  await new Promise((r) => { v.addEventListener("seeked", r, { once: true }); v.currentTime = t; });
  await sleep(250);
}

// mean RGB of the preview canvas (renderer readback)
export function previewStats() {
  const app = window.__sfx, R = app.renderer;
  // draw + read in the same task (the canvas isn't preserved after compositing)
  app.uploadVideoFrame();
  app.drawAt(document.querySelector("#video").currentTime);
  const px = R.readPixels();
  let r = 0, g = 0, b = 0; const n = px.length / 4;
  for (let i = 0; i < px.length; i += 4) { r += px[i]; g += px[i + 1]; b += px[i + 2]; }
  return { w: R.width, h: R.height, mean: [r / n, g / n, b / n].map((v) => +v.toFixed(1)) };
}

export async function run({ clip = "Rave_starlight4.mp4", stack = null, exportIt = false, saveAs = null } = {}) {
  const app = await open(clip);
  const tl = app.timeline, L = app.project.lanes.map((l) => l.id);
  const plan = stack || [
    ["rgb-split", 0, 0, 3, { audioBand: "kick" }],
    ["st-kaleidoscope-effect", 0, 3.2, 2.5, {}],
    ["ghost-trails", 1, 1, 4, {}],
    ["film-grade", 2, 0, app.info.duration, {}],
  ];
  const added = [];
  for (const [id, lane, start, dur, extra] of plan) {
    const s = tl.addSegment(id, L[lane], start, dur);
    if (!s) { added.push(`FAILED ${id}`); continue; }
    Object.assign(s, extra); added.push(`${id}@${lane}`);
  }
  await sleep(600);
  const report = { info: app.info, added, entries: [...app.entries].map(([k, e]) => `${k}:${e.error ? "ERR " + e.error.slice(0, 120) : "ok"}`), frames: {} };
  // preview with and without effects at a few times
  for (const t of [0.5, 2.0, 4.0]) {
    await seek(t);
    report.frames[t] = { fx: document.querySelector("#preview-info").textContent, ...previewStats() };
  }
  if (exportIt) {
    const res = await app.doExport();
    if (!res) { report.exportError = String(app.lastError); return report; }
    report.export = res.stats;
    const name = saveAs || clip.replace(/\.[^.]+$/, "") + "_e2e.mp4";
    const r = await fetch(`/__dev/save?name=${encodeURIComponent(name)}`, { method: "POST", body: res.blob });
    report.saved = (await r.json()).saved;
  }
  return report;
}
