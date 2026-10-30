import { defineConfig } from "vite";
import path from "node:path";
import fs from "node:fs";
import { buildRegistry, EFFECTS_DIR } from "./scripts/build-registry.mjs";

// Rebuild public/effects/index.json on start and whenever an effect file changes,
// then tell the page so the library refreshes without a reload.
function effectsRegistry() {
  let timer = null;
  return {
    name: "sizzlefx-effects-registry",
    buildStart() { buildRegistry(); },
    configureServer(server) {
      // dev-only: tests POST exported files here so ffprobe can check them
      server.middlewares.use("/__dev/save", (req, res) => {
        if (req.method !== "POST") { res.statusCode = 405; return res.end(); }
        const name = path.basename(new URL(req.url, "http://x").searchParams.get("name") || "out.bin");
        const dir = path.resolve("test-media", "_out");
        fs.mkdirSync(dir, { recursive: true });
        const ws = fs.createWriteStream(path.join(dir, name));
        req.pipe(ws);
        ws.on("finish", () => { res.setHeader("content-type", "application/json"); res.end(JSON.stringify({ saved: path.join(dir, name) })); });
      });
      server.watcher.add(EFFECTS_DIR);
      const onChange = (file) => {
        if (!file.startsWith(EFFECTS_DIR) || file.endsWith("index.json")) return;
        clearTimeout(timer);
        timer = setTimeout(() => {
          buildRegistry({ quiet: false });
          server.ws.send({ type: "custom", event: "effects-changed", data: { file: path.relative(EFFECTS_DIR, file) } });
        }, 150);
      };
      server.watcher.on("add", onChange);
      server.watcher.on("change", onChange);
      server.watcher.on("unlink", onChange);
    },
  };
}

// ONNX Runtime loads its wasm runtime with a dynamic import that Vite would rewrite,
// so the whole runtime (bundle + asyncify wasm) is served untouched from /ort/ and
// loaded by absolute URL (src/mask/ort.js).
// Copied when the config loads (before Vite indexes public/).
function copyOrtRuntime() {
  const src = path.resolve("node_modules/onnxruntime-web/dist"), dst = path.resolve("public/ort");
  if (!fs.existsSync(src)) return;
  fs.mkdirSync(dst, { recursive: true });
  for (const f of ["ort.all.bundle.min.mjs", "ort-wasm-simd-threaded.jsep.mjs", "ort-wasm-simd-threaded.jsep.wasm"]) {
    const a = path.join(src, f), b = path.join(dst, f);
    if (!fs.existsSync(b) || fs.statSync(b).size !== fs.statSync(a).size) fs.copyFileSync(a, b);
  }
}
copyOrtRuntime();

export default defineConfig({
  plugins: [effectsRegistry()],
  optimizeDeps: { exclude: ["onnxruntime-web"] },
  // /api -> the Python render server (Phase 5, server/app.py on :8790)
  server: {
    port: 5180, strictPort: false,
    proxy: { "/api": { target: "http://127.0.0.1:8790", changeOrigin: true } },
    // the demo recorder's Chrome profile holds locked files (EBUSY crashed the watcher)
    watch: { ignored: ["**/demo/**", "**/demo2/**", "**/server/**", "**/test-media/**", "**/dist/**"] },
  },
  build: { target: "es2022" },
  worker: { format: "es" },
});
