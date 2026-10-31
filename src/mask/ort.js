// Loads ONNX Runtime Web (WebGPU + wasm fallback) from <base>/ort/ by absolute URL so
// Vite never rewrites its internal dynamic imports. Works in pages and workers.
//
// We use the JSEP WebGPU backend (ort.all bundle). On 1.24.1 the newer native
// WebGPU EP (ort.webgpu bundle) dies on RVM with "Buffer used in submit while
// destroyed" on the very first run (GTX 1080 Ti, Chrome, 2026-10-29).
import { BASE } from "../base.js";

let ortPromise = null;

export function loadOrt() {
  if (!ortPromise) {
    ortPromise = (async () => {
      const base = new URL(BASE + "ort/", self.location.origin).href;
      const ort = await import(/* @vite-ignore */ base + "ort.all.bundle.min.mjs");
      ort.env.wasm.wasmPaths = base;
      ort.env.wasm.numThreads = self.crossOriginIsolated ? Math.min(4, navigator.hardwareConcurrency || 2) : 1;
      ort.env.logLevel = "error";
      return ort;
    })();
  }
  return ortPromise;
}

// Model locations: local copies first (dev / self-hosted), then the public originals.
export const MODELS = {
  rvm: {
    label: "Robust Video Matting (MobileNetV3)",
    // official release (PeterL1n/RobustVideoMatting v1.0.0); self-host it in /models/ for production
    urls: [BASE + "models/rvm_mobilenetv3_fp32.onnx", "https://github.com/PeterL1n/RobustVideoMatting/releases/download/v1.0.0/rvm_mobilenetv3_fp32.onnx"],
    // JSEP can't do AveragePool(ceil_mode=1). With frame sizes that are multiples of 32
    // and downsample 0.5, every pool sees even sizes, so ceil == floor: patch it to 0.
    patch: patchCeilMode,
  },
  sam2Encoder: {
    label: "SAM 2.1 tiny vision encoder",
    urls: [BASE + "models/sam2.1-tiny/vision_encoder.onnx", "https://huggingface.co/onnx-community/sam2.1-hiera-tiny-ONNX/resolve/main/onnx/vision_encoder.onnx"],
    data: "vision_encoder.onnx_data",
  },
  sam2Decoder: {
    label: "SAM 2.1 tiny prompt decoder",
    urls: [BASE + "models/sam2.1-tiny/prompt_encoder_mask_decoder.onnx", "https://huggingface.co/onnx-community/sam2.1-hiera-tiny-ONNX/resolve/main/onnx/prompt_encoder_mask_decoder.onnx"],
    data: "prompt_encoder_mask_decoder.onnx_data",
  },
};

// First URL that answers (HEAD), so a self-hosted copy wins over the network.
async function pickUrl(urls) {
  for (const u of urls) {
    try { const r = await fetch(u, { method: "HEAD" }); if (r.ok && !(r.headers.get("content-type") || "").includes("text/html")) return u; } catch (_) {}
  }
  throw new Error("model not reachable: " + urls[0]);
}

// Flip every AveragePool ceil_mode=1 attribute to 0 in the raw protobuf
// (bytes: 0a 09 "ceil_mode" 18 01 -> ... 18 00).
function patchCeilMode(bytes) {
  const pat = [0x0a, 0x09, ...new TextEncoder().encode("ceil_mode"), 0x18, 0x01];
  let hits = 0;
  outer: for (let i = 0; i <= bytes.length - pat.length; i++) {
    for (let k = 0; k < pat.length; k++) if (bytes[i + k] !== pat[k]) continue outer;
    bytes[i + pat.length - 1] = 0; hits++;
  }
  return hits;
}

export async function createSession(key, { gpu = true } = {}) {
  const ort = await loadOrt();
  const m = MODELS[key];
  const url = await pickUrl(m.urls);
  const opts = { executionProviders: gpu ? ["webgpu", "wasm"] : ["wasm"], graphOptimizationLevel: "all" };
  if (m.data) opts.externalData = [{ path: m.data, data: url.replace(/[^/]+$/, m.data) }];
  let model = url;
  if (m.patch) { model = new Uint8Array(await (await fetch(url)).arrayBuffer()); m.patch(model); }
  const session = await ort.InferenceSession.create(model, opts);
  return { ort, session, url };
}
