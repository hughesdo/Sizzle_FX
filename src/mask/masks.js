// Mask tracks for the open video: bake (via bake.worker.js), list, persist, delete,
// and the SAM2 interactive selection step.

import { MaskTrack, maskSize, saveTrack, loadTracks, deleteTrack, videoKeyOf } from "./maskTrack.js";

export const PROVIDERS = {
  rvm: { label: "Auto person (RVM)", short: "person" },
  key: { label: "Green screen key", short: "key" },
  sam2: { label: "Click to select (SAM 2)", short: "select" },
};

export class MaskManager {
  constructor({ onChange, onFrame, onStatus }) {
    this.tracks = []; this.info = null; this.file = null;
    this.onChange = onChange || (() => {}); this.onFrame = onFrame || (() => {}); this.onStatus = onStatus || (() => {});
    this.worker = null; this.job = null;
  }

  async setVideo(file, info) {
    this.cancel();
    this.file = file; this.info = info;
    this.tracks = info ? await loadTracks(videoKeyOf(info)) : [];
    this.onChange();
  }

  get(id) { return this.tracks.find((t) => t.id === id) || null; }
  get busy() { return !!this.job; }

  _worker() {
    if (!this.worker) {
      this.worker = new Worker(new URL("./bake.worker.js", import.meta.url), { type: "module" });
      this.worker.onmessage = (e) => this._onMessage(e.data);
      this.worker.onerror = (e) => this._finish(new Error(e.message || "mask worker crashed"));
    }
    return this.worker;
  }

  _onMessage(m) {
    const job = this.job;
    if (m.type === "select") { this._selectResolve?.(m); this._selectResolve = null; return; }
    if (m.type === "error" && this._selectReject) { this._selectReject(new Error(m.message)); this._selectReject = this._selectResolve = null; return; }
    if (!job) return;
    if (m.type === "status") this.onStatus(job.track, m.msg);
    else if (m.type === "frame") { job.track.setFrame(m.i, m.alpha); this.onFrame(job.track, m.i); }
    else if (m.type === "progress") { job.progress = m; this.onStatus(job.track, `${m.done}/${m.total} frames · ${m.fps.toFixed(1)} fps`); }
    else if (m.type === "done") this._finish(null);
    else if (m.type === "error") this._finish(new Error(m.message));
  }

  async _finish(err) {
    const job = this.job; this.job = null;
    if (!job) return;
    if (err) {
      this.tracks = this.tracks.filter((t) => t !== job.track);
      if (this.worker && /cancel/i.test(err.message) === false) { this.worker.terminate(); this.worker = null; }
      this.onChange();
      job.reject(err);
      return;
    }
    job.track.filled = job.track.frames;
    await saveTrack(videoKeyOf(this.info), job.track);
    this.onChange();
    job.resolve(job.track);
  }

  /** provider: rvm | key | sam2. prompt (sam2): {frameIndex, points:[{x,y,label}]} */
  bake(provider, { params = {}, prompt = null, name = null } = {}) {
    if (!this.info) return Promise.reject(new Error("open a video first"));
    if (this.job) return Promise.reject(new Error("a mask is already baking"));
    const { width, height } = maskSize(this.info);
    const n = this.tracks.filter((t) => t.provider === provider).length + 1;
    const track = new MaskTrack({
      id: `m${Date.now().toString(36)}`, name: name || `${PROVIDERS[provider].short} ${n}`,
      provider, width, height, frames: this.info.frames, params,
    });
    this.tracks.push(track);
    this.onChange();
    return new Promise((resolve, reject) => {
      this.job = { track, resolve, reject, progress: null };
      const { fps, firstTs, frames } = this.info;
      this._worker().postMessage({ type: "bake", file: this.file, provider, width, height, fps, firstTs, frames, params, prompt });
    });
  }

  cancel() {
    if (this.job && this.worker) { this.worker.terminate(); this.worker = null; this._finish(new Error("cancelled")); }
  }

  /** SAM2: segment one frame from clicked points (normalised, top-left origin). Returns {alpha, width, height, score}. */
  select(frameIndex, points, level = 0) {
    if (this.job) return Promise.reject(new Error("wait for the current bake to finish"));
    const { width, height } = maskSize(this.info);
    return new Promise((resolve, reject) => {
      this._selectResolve = (m) => resolve({ ...m, width, height });
      this._selectReject = reject;
      const { fps, firstTs } = this.info;
      this._worker().postMessage({ type: "sam2-select", file: this.file, frameIndex, fps, firstTs, width, height, points, level });
    });
  }

  async remove(id) {
    if (this.job?.track.id === id) this.cancel();
    this.tracks = this.tracks.filter((t) => t.id !== id);
    if (this.info) await deleteTrack(videoKeyOf(this.info), id);
    this.onChange();
  }

  /** add a finished track that came from elsewhere (a saved project) and persist it in OPFS */
  async adopt(track) {
    if (this.get(track.id)) return;
    this.tracks.push(track);
    this.tracks.sort((a, b) => a.id.localeCompare(b.id));
    if (this.info) await saveTrack(videoKeyOf(this.info), track);
    this.onChange();
  }

  async rename(id, name) {
    const t = this.get(id); if (!t) return;
    t.name = name;
    if (!this.job || this.job.track !== t) await saveTrack(videoKeyOf(this.info), t);
    this.onChange();
  }
}
