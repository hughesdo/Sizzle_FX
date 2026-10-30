// Browser export: Mediabunny decode (frame-exact, sequential) -> Renderer (same
// frame builder as the preview) -> WebCodecs H.264 High -> MP4 with fast start.
// Audio: source AAC-LC packets are copied untouched; anything else is re-encoded
// to AAC-LC 192k so the file is accepted by X / YouTube / Instagram.

import {
  Output, Mp4OutputFormat, BufferTarget, CanvasSource, EncodedAudioPacketSource, AudioSampleSource,
  EncodedPacketSink, AudioSampleSink, CanvasSink, Quality, canEncodeAudio,
} from "mediabunny";
import { openInput } from "./source.js";
import { Renderer } from "../render/renderer.js";
import { buildFrame } from "../project.js";

export const PRESETS = {
  // qp = constant-quantizer target (CRF-like); bpp = bits/pixel/frame for the
  // bitrate fallback on encoders without quantizer mode (1080p30: ~16 / ~25 Mbps)
  social: { label: "X / YouTube (H.264 High, balanced)", qp: 20, bpp: 0.26 },
  max: { label: "Max quality (bigger file)", qp: 16, bpp: 0.4 },
};

// H.264 High profile codec string with a level that fits the frame size + rate.
export function avcCodecString(w, h, fps) {
  const mbs = Math.ceil(w / 16) * Math.ceil(h / 16), mbps = mbs * fps;
  const levels = [[0x28, 8192, 245760], [0x2a, 8704, 522240], [0x32, 22080, 589824], [0x33, 36864, 983040], [0x34, 36864, 2073600]];
  const lv = levels.find(([, fs, rate]) => mbs <= fs && mbps <= rate) || levels.at(-1);
  return `avc1.6400${lv[0].toString(16)}`;
}

export function targetBitrate(w, h, fps, bpp) { return Math.round(w * h * fps * bpp); }

const isAacLc = (codecString) => /^mp4a\.40\.0?2$/i.test(codecString || "");

/**
 * opts: { file, info, project, effects(Map), loadSources(effect)->sources, analysis,
 *         preset, onProgress(p, msg), signal }
 * Returns { blob, stats }.
 */
export async function exportVideo(opts) {
  const { file, info, project, effects, loadSources, analysis, preset = PRESETS.social, onProgress = () => {}, signal, maskTracks = [] } = opts;
  const W = info.width - (info.width % 2), H = info.height - (info.height % 2), fps = info.fps;
  const input = openInput(file);
  const vt = await input.getPrimaryVideoTrack();
  const at = await input.getPrimaryAudioTrack();

  // renderer on its own canvas, full output size
  const canvas = new OffscreenCanvas(W, H);
  const R = new Renderer(canvas, { preserveDrawingBuffer: true });
  R.resize(W, H);
  const entries = new Map();
  for (const seg of project.segments) {
    const fx = effects.get(seg.effectId);
    if (fx && !entries.has(fx.id)) entries.set(fx.id, R.ensureEffect(fx, await loadSources(fx)));
  }

  const output = new Output({ format: new Mp4OutputFormat({ fastStart: "in-memory" }), target: new BufferTarget() });
  const bitrate = targetBitrate(W, H, fps, preset.bpp);
  let encoderConfig = null;
  const videoSource = new CanvasSource(canvas, {
    codec: "avc",
    fullCodecString: avcCodecString(W, H, fps),
    quality: new Quality({ quantizer: preset.qp, bitrate }),
    keyFrameInterval: 2,
    latencyMode: "quality",
    onEncoderConfig: (c) => { encoderConfig = { ...c }; },
  });
  output.addVideoTrack(videoSource, { frameRate: fps });

  // ---- audio: passthrough AAC-LC, else re-encode to AAC-LC
  let audioMode = "none", audioSource = null, audioTrackInfo = null;
  if (at) {
    const dc = await at.getDecoderConfig();
    audioTrackInfo = { codec: at.codec, codecString: dc?.codec };
    if (at.codec === "aac" && isAacLc(dc?.codec)) {
      audioMode = "copy";
      audioSource = new EncodedAudioPacketSource("aac");
    } else {
      if (!(await canEncodeAudio("aac", { sampleRate: 48000, numberOfChannels: 2, quality: new Quality({ bitrate: 192000 }) }))) {
        const { registerAacEncoder } = await import("@mediabunny/aac-encoder");
        registerAacEncoder();
        audioMode = "encode-wasm";
      } else audioMode = "encode";
      audioSource = new AudioSampleSource({ codec: "aac", quality: new Quality({ bitrate: 192000 }) });
    }
    output.addAudioTrack(audioSource);
  }

  await output.start();

  const abort = () => { if (signal?.aborted) throw new DOMException("export cancelled", "AbortError"); };

  const audioPump = (async () => {
    if (audioMode === "none") return;
    if (audioMode === "copy") {
      const dc = await at.getDecoderConfig();
      const sink = new EncodedPacketSink(at);
      let first = true;
      for await (const packet of sink.packets()) {
        abort();
        await audioSource.add(packet, first ? { decoderConfig: dc } : undefined);
        first = false;
      }
    } else {
      const sink = new AudioSampleSink(at);
      for await (const sample of sink.samples()) { abort(); await audioSource.add(sample); sample.close(); }
    }
    audioSource.close();
  })();

  const videoPump = (async () => {
    const sink = new CanvasSink(vt, { width: W, height: H, fit: "fill", poolSize: 2 });
    const t0 = info.firstTs || 0;
    const total = Math.max(1, info.frames);
    let i = 0, lastT = 0, started = performance.now();
    for await (const wc of sink.canvases()) {
      abort();
      const time = Math.max(0, wc.timestamp - t0);
      R.uploadSource(wc.canvas);
      // frame index from the timestamp (same mapping as the preview and the mask bake)
      const index = Math.round(time * fps);
      const frame = buildFrame(project, { time, index, dt: i ? time - lastT : 1 / fps, analysis, effects, entries, maskTracks });
      R.render(frame);
      // constant frame rate output: snap each frame to the fps grid (fixes MKV/WebM
      // millisecond jitter); audio keeps its own exact timestamps
      const outT = Math.max(0, Math.round(wc.timestamp * fps) / fps);
      await videoSource.add(outT, 1 / fps);
      lastT = time; i++;
      if (i % 5 === 0) {
        const el = (performance.now() - started) / 1000;
        onProgress(Math.min(0.99, i / total), `frame ${i}/${total} · ${(i / el).toFixed(1)} fps`);
      }
    }
    videoSource.close();
    return i;
  })();

  const [frames] = await Promise.all([videoPump, audioPump]);
  onProgress(0.995, "finalizing mp4…");
  await output.finalize();
  const blob = new Blob([output.target.buffer], { type: "video/mp4" });
  onProgress(1, "done");
  return { blob, stats: { frames, width: W, height: H, fps, bitrate, codec: encoderConfig?.codec, bitrateMode: encoderConfig?.bitrateMode, audioMode, audio: audioTrackInfo, bytes: blob.size } };
}
