import { test } from "node:test";
import assert from "node:assert/strict";
import { analyzeAudio, sampleAnalysis, fftRowAt } from "../src/audio/analysis.js";
import { snapFps } from "../src/media/source.js";

// 8 s of 120 bpm kicks (decaying 60 Hz bursts) + a little noise
function synth(sr = 48000, secs = 8) {
  const x = new Float32Array(sr * secs);
  for (let i = 0; i < x.length; i++) {
    const t = i / sr, ph = t % 0.5;
    x[i] = Math.sin(2 * Math.PI * 60 * t) * Math.exp(-ph * 18) * 0.8 + (Math.random() - 0.5) * 0.01;
  }
  return x;
}

test("analysis finds the tempo and produces every field effects use", async () => {
  const A = await analyzeAudio(synth(), 48000);
  assert.ok(Math.abs(A.bpm - 120) < 3 || Math.abs(A.bpm - 60) < 2 || Math.abs(A.bpm - 240) < 4, `bpm ${A.bpm}`);
  assert.equal(A.peaks.length, 1200);
  assert.equal(A.fft.rows.length, A.fft.n * 1024);
  const s = sampleAnalysis(A, 2.0);
  for (const k of ["bass", "lowmid", "mid", "high", "treble", "level", "kick", "snare", "hat", "flow", "beat", "bar"]) assert.equal(typeof s[k], "number", k);
  const row = fftRowAt(A, 2.0);
  assert.equal(row.length, 1024);
  // low bins of a 60 Hz signal are hot, top bins are quiet
  assert.ok(row[512 + 1] > row[512 + 500], "fft row ordering");
});

test("sampleAnalysis works with no audio", () => {
  const s = sampleAnalysis(null, 1.5);
  assert.equal(s.level, 0);
  assert.equal(fftRowAt(null, 1), null);
});

test("snapFps picks the closest common rate", () => {
  assert.equal(snapFps(24), 24);
  assert.equal(snapFps(23.976), 23.976);
  assert.equal(snapFps(24000 / 1001), 23.976);
  assert.equal(snapFps(29.97), 29.97);
  assert.equal(snapFps(59.94), 59.94);
  assert.equal(snapFps(17.5), 17.5);
});
