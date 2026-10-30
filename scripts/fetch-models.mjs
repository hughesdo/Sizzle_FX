// Downloads the mask models into public/models/ (gitignored, ~170 MB).
//   node scripts/fetch-models.mjs
// RVM: official PeterL1n/RobustVideoMatting v1.0.0 release.
// SAM 2.1 tiny: onnx-community/sam2.1-hiera-tiny-ONNX (fp32; Pascal GPUs are weak at fp16).

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const OUT = path.join(ROOT, "public", "models");
const SAM = "https://huggingface.co/onnx-community/sam2.1-hiera-tiny-ONNX/resolve/main/onnx";
const FILES = [
  ["rvm_mobilenetv3_fp32.onnx", "https://github.com/PeterL1n/RobustVideoMatting/releases/download/v1.0.0/rvm_mobilenetv3_fp32.onnx"],
  ["sam2.1-tiny/vision_encoder.onnx", `${SAM}/vision_encoder.onnx`],
  ["sam2.1-tiny/vision_encoder.onnx_data", `${SAM}/vision_encoder.onnx_data`],
  ["sam2.1-tiny/prompt_encoder_mask_decoder.onnx", `${SAM}/prompt_encoder_mask_decoder.onnx`],
  ["sam2.1-tiny/prompt_encoder_mask_decoder.onnx_data", `${SAM}/prompt_encoder_mask_decoder.onnx_data`],
];

for (const [rel, url] of FILES) {
  const dst = path.join(OUT, rel);
  if (fs.existsSync(dst) && fs.statSync(dst).size > 1000) { console.log(`have ${rel}`); continue; }
  fs.mkdirSync(path.dirname(dst), { recursive: true });
  process.stdout.write(`get  ${rel} … `);
  const r = await fetch(url);
  if (!r.ok) { console.log(`FAILED ${r.status}`); process.exitCode = 1; continue; }
  fs.writeFileSync(dst, Buffer.from(await r.arrayBuffer()));
  console.log(`${(fs.statSync(dst).size / 1e6).toFixed(1)} MB`);
}
