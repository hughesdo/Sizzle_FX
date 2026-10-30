// Runs the whole-track analysis off the main thread.
import { analyzeAudio } from "./analysis.js";

self.onmessage = async (e) => {
  const { mono, sampleRate } = e.data;
  try {
    const A = await analyzeAudio(mono, sampleRate, (p) => self.postMessage({ type: "progress", p }));
    self.postMessage({ type: "done", analysis: A }, [A.fft.rows.buffer]);
  } catch (err) {
    self.postMessage({ type: "error", message: String(err && err.message || err) });
  }
};
