// Library thumbnails rendered from YOUR video: one small frame run through every
// effect (with the default mask, so Body effects show properly). Runs in small
// batches so the UI stays responsive; restarts when the video or registry changes.

import { Renderer } from "../render/renderer.js";
import { buildFrame, newProject, newSegment } from "../project.js";

export const THUMB_W = 160, THUMB_H = 90;

export class ThumbMaker {
  constructor() {
    this.canvas = document.createElement("canvas");
    this.R = new Renderer(this.canvas, { preserveDrawingBuffer: true });
    this.R.resize(THUMB_W, THUMB_H);
    this.urls = new Map(); // effectId -> object URL
    this.gen = 0;
  }

  clear() { for (const u of this.urls.values()) URL.revokeObjectURL(u); this.urls.clear(); }

  /**
   * opts: { source (canvas), effects (array), loadSources(fx), time, analysis, maskTracks, frameIndex, onThumb(id,url) }
   */
  async run(opts) {
    const gen = ++this.gen;
    this.clear();
    const { source, effects, loadSources, time = 1, analysis = null, maskTracks = [], frameIndex = 0, onThumb } = opts;
    const R = this.R;
    const project = newProject({ name: "thumb", size: 0, duration: time + 10, fps: 30, width: THUMB_W, height: THUMB_H });
    const map = new Map(effects.map((e) => [e.id, e]));
    let n = 0;
    for (const fx of effects) {
      if (gen !== this.gen) return;
      let entry;
      try { entry = R.ensureEffect(fx, await loadSources(fx)); } catch (_) { continue; }
      if (entry.error) continue;
      const seg = { ...newSegment(fx, "L1", 0, time + 10), id: "thumb-" + fx.id, audioBand: "level", react: 1.5 };
      project.segments = [seg];
      R.uploadSource(source);
      // a few frames so feedback / history effects have something to show
      for (let k = 2; k >= 0; k--) {
        const f = buildFrame(project, { time: time - k / 30, index: frameIndex - k, dt: 1 / 30, analysis, effects: map, entries: new Map([[fx.id, entry]]), maskTracks });
        R.render(f);
      }
      R.dropSegment(seg.id);
      const blob = await new Promise((res) => this.canvas.toBlob(res, "image/jpeg", 0.8));
      if (gen !== this.gen || !blob) return;
      const url = URL.createObjectURL(blob);
      this.urls.set(fx.id, url);
      onThumb && onThumb(fx.id, url);
      if (++n % 6 === 0) await new Promise((r) => setTimeout(r, 0)); // yield to the UI
    }
  }
}
