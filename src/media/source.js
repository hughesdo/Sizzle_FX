// Opening a video: probe it, decode its audio for analysis, grab timeline thumbnails.
import { Input, BlobSource, ALL_FORMATS, AudioBufferSink, CanvasSink, EncodedPacketSink } from "mediabunny";

const COMMON_FPS = [23.976, 24, 25, 29.97, 30, 48, 50, 59.94, 60, 120];

// Snap to the CLOSEST common rate, within 0.04% (23.976 and 24 are only 0.1% apart).
export function snapFps(f) {
  let best = null, bd = 0.0004;
  for (const c of COMMON_FPS) { const d = Math.abs(f - c) / c; if (d < bd) { bd = d; best = c; } }
  return best ?? Math.round(f * 1000) / 1000;
}

export function openInput(file) {
  return new Input({ source: new BlobSource(file), formats: ALL_FORMATS });
}

export async function probeVideo(file) {
  const input = openInput(file);
  const vt = await input.getPrimaryVideoTrack();
  if (!vt) throw new Error("no video track in this file");
  const at = await input.getPrimaryAudioTrack();
  const duration = await input.computeDuration();
  // fps from the span of the first ~120 presentation timestamps. Exact for MP4/MOV,
  // and robust to MKV/WebM millisecond rounding (41/42 ms frame durations).
  // (A whole-track packet average turns a short 24 fps clip into 23.976.)
  // Packets arrive in DECODE order: with B-frame pyramids the first 121 packets can hold
  // timestamps from beyond the 121st frame, so read extra, sort, and keep the first 121.
  let pts = [];
  const ps = new EncodedPacketSink(vt);
  for await (const p of ps.packets(undefined, undefined, { metadataOnly: true })) { pts.push(p.timestamp); if (pts.length >= 121 + 32) break; }
  pts.sort((a, b) => a - b);
  pts = pts.slice(0, 121);
  let fps = pts.length > 2 ? (pts.length - 1) / (pts.at(-1) - pts[0]) : 0;
  if (!(fps > 1 && fps < 241)) fps = (await vt.computePacketStats(240)).averagePacketRate || 30;
  fps = snapFps(fps);
  const firstTs = await vt.getFirstTimestamp();
  let audio = null;
  if (at) {
    const cfg = await at.getDecoderConfig();
    audio = { codec: at.codec, codecString: cfg?.codec || at.codec, sampleRate: at.sampleRate, channels: at.numberOfChannels };
  }
  return {
    name: file.name, size: file.size, lastModified: file.lastModified,
    width: vt.displayWidth, height: vt.displayHeight, rotation: vt.rotation,
    codec: vt.codec, fps, duration, firstTs, audio,
    frames: Math.round((Math.min(duration, await vt.computeDuration()) - firstTs) * fps),
  };
}

// Decode the audio track to one mono Float32Array (for analysis).
export async function decodeMonoAudio(file, onProgress) {
  const input = openInput(file);
  const at = await input.getPrimaryAudioTrack();
  if (!at) return null;
  const duration = await input.computeDuration();
  const sr = at.sampleRate;
  const mono = new Float32Array(Math.ceil(duration * sr) + sr);
  const sink = new AudioBufferSink(at);
  let last = 0;
  for await (const { buffer, timestamp } of sink.buffers()) {
    const off = Math.max(0, Math.round(timestamp * sr));
    const ch = buffer.numberOfChannels, n = buffer.length;
    const data = []; for (let c = 0; c < ch; c++) data.push(buffer.getChannelData(c));
    for (let i = 0; i < n && off + i < mono.length; i++) {
      let s = 0; for (let c = 0; c < ch; c++) s += data[c][i];
      mono[off + i] = s / ch;
    }
    if (onProgress && timestamp - last > 2) { last = timestamp; onProgress(Math.min(1, timestamp / duration)); }
  }
  return { mono: mono.subarray(0, Math.ceil(duration * sr)), sampleRate: sr };
}

// One frame at time t, drawn into a canvas of the given size (library thumbnails).
export async function frameCanvasAt(file, t, width, height) {
  const input = openInput(file);
  const vt = await input.getPrimaryVideoTrack();
  const sink = new CanvasSink(vt, { width, height, fit: "cover" });
  const wc = await sink.getCanvas(t);
  return wc ? wc.canvas : null;
}

// Small thumbnails along the timeline. Yields {time, canvas} as they decode.
export async function* thumbnails(file, count, height = 48) {
  const input = openInput(file);
  const vt = await input.getPrimaryVideoTrack();
  const duration = await input.computeDuration();
  const sink = new CanvasSink(vt, { height, fit: "contain" });
  const times = [];
  for (let i = 0; i < count; i++) times.push((i + 0.5) / count * duration);
  for await (const wc of sink.canvasesAtTimestamps(times)) {
    if (wc) yield { time: wc.timestamp, canvas: wc.canvas };
  }
}
