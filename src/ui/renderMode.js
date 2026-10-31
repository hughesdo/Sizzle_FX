// Detect what this browser/GPU can do and pick a render mode. "server" = the Python
// render server (server/app.py: ModernGL + ffmpeg), offered when /api/status answers.

import { HOSTED } from "../base.js";

export async function detectCapabilities(w = 1920, h = 1080, fps = 30) {
  const caps = { webgl2: false, floatTargets: false, gpu: "", h264High: false, aacEncode: false, webgpu: !!navigator.gpu, server: false };
  try {
    const c = document.createElement("canvas");
    const gl = c.getContext("webgl2");
    if (gl) {
      caps.webgl2 = true;
      caps.floatTargets = !!gl.getExtension("EXT_color_buffer_float");
      const dbg = gl.getExtension("WEBGL_debug_renderer_info");
      caps.gpu = dbg ? gl.getParameter(dbg.UNMASKED_RENDERER_WEBGL) : gl.getParameter(gl.RENDERER);
      gl.getExtension("WEBGL_lose_context")?.loseContext();
    }
  } catch (_) {}
  try {
    if (window.VideoEncoder) {
      const r = await VideoEncoder.isConfigSupported({ codec: "avc1.640033", width: w, height: h, bitrate: 20e6, framerate: fps });
      caps.h264High = !!r.supported;
    }
  } catch (_) {}
  try {
    if (window.AudioEncoder) {
      const r = await AudioEncoder.isConfigSupported({ codec: "mp4a.40.2", sampleRate: 48000, numberOfChannels: 2, bitrate: 192000 });
      caps.aacEncode = !!r.supported;
    }
  } catch (_) {}
  if (!HOSTED) try {
    const ctl = new AbortController(); const t = setTimeout(() => ctl.abort(), 800);
    const r = await fetch("/api/status", { signal: ctl.signal }); clearTimeout(t);
    // static hosts / the Vite dev server answer unknown paths with index.html, so require JSON
    if (r.ok && (r.headers.get("content-type") || "").includes("json")) { const j = await r.json(); caps.server = !!j.render_ready; caps.serverInfo = j; }
  } catch (_) {}
  return caps;
}

export function chooseDefaultMode(caps) {
  if (caps.webgl2 && caps.h264High) return "browser";
  if (caps.server) return "server";
  return "browser";
}
