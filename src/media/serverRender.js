// Export via the Python render server (server/app.py): same effect files rendered by
// ModernGL on the local GPU, encoded by ffmpeg (NVENC or libx264). We send the video,
// the project, the browser's audio analysis and the baked mask tracks so the server
// renders exactly what the preview shows.

async function gzip(bytes) {
  const s = new Blob([bytes]).stream().pipeThrough(new CompressionStream("gzip"));
  return new Blob([await new Response(s).arrayBuffer()]);
}

// only what the renderer reads (typed arrays -> plain arrays)
function analysisPayload(A) {
  if (!A) return null;
  const arr = (a) => Array.from(a, (v) => +v.toFixed(5));
  return {
    fps: A.fps, n: A.n, sampleRate: A.sampleRate,
    bands: Object.fromEntries(Object.entries(A.bands).map(([k, v]) => [k, arr(v)])),
    level: arr(A.level), kick: arr(A.kick), snare: arr(A.snare), hat: arr(A.hat), flow: arr(A.flow),
    beats: A.beats, downbeats: A.downbeats, fft: { fps: A.fft.fps, n: A.fft.n },
  };
}

function upload(form, onUpload, signal) {
  return new Promise((resolve, reject) => {
    const x = new XMLHttpRequest();
    x.open("POST", "/api/render");
    x.upload.onprogress = (e) => e.lengthComputable && onUpload(e.loaded / e.total);
    x.onload = () => { try { const j = JSON.parse(x.responseText); x.status < 300 ? resolve(j) : reject(new Error(j.error || j.detail || x.statusText)); } catch (err) { reject(err); } };
    x.onerror = () => reject(new Error("could not reach the render server"));
    signal?.addEventListener("abort", () => { x.abort(); reject(new DOMException("export cancelled", "AbortError")); });
    x.send(form);
  });
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

/** opts: { file, info, project, analysis, maskTracks, preset, encoder, onProgress(p,msg), signal } -> {blob, stats} */
export async function serverExport(opts) {
  const { file, info, project, analysis, maskTracks = [], preset = "social", encoder = "auto", onProgress = () => {}, signal } = opts;
  const form = new FormData();
  form.append("video", file, file.name);
  form.append("project", JSON.stringify({ ...project, video: { ...project.video, width: info.width, height: info.height, fps: info.fps, frames: info.frames } }));
  const ap = analysisPayload(analysis);
  if (ap) { form.append("analysis", JSON.stringify(ap)); form.append("fft", new Blob([analysis.fft.rows]), "fft.bin"); }
  const used = maskTracks.filter((t) => t.filled === t.frames);
  if (used.length) {
    form.append("masks", JSON.stringify(used.map((t) => ({ id: t.id, width: t.width, height: t.height, frames: t.frames }))));
    for (const t of used) {
      onProgress(0, `packing mask ${t.name}…`);
      form.append(`mask_${t.id}`, await gzip(t.data), `mask_${t.id}.bin.gz`);
      form.append(`stats_${t.id}`, new Blob([t.stats]), `stats_${t.id}.bin`);
    }
  }
  form.append("preset", preset);
  form.append("encoder", encoder);

  const job = await upload(form, (p) => onProgress(p * 0.1, `uploading ${(p * 100).toFixed(0)}%`), signal);
  const cancel = () => fetch(`/api/jobs/${job.id}`, { method: "DELETE" }).catch(() => {});
  signal?.addEventListener("abort", cancel);
  let st = job;
  while (true) {
    if (signal?.aborted) throw new DOMException("export cancelled", "AbortError");
    await sleep(400);
    st = await (await fetch(`/api/jobs/${job.id}`)).json();
    if (st.state === "queued") onProgress(0.1, st.position > 0 ? `queued (${st.position} ahead)` : st.message || "starting…");
    else if (st.state === "rendering") onProgress(0.1 + 0.88 * (st.frame / Math.max(1, st.total)), `server: frame ${st.frame}/${st.total} · ${st.fps} fps`);
    else if (st.state === "encoding") onProgress(0.98, "server: finishing mp4…");
    else if (st.state === "done") break;
    else if (st.state === "cancelled") throw new DOMException("export cancelled", "AbortError");
    else if (st.state === "error") throw new Error(st.message || "server render failed");
  }
  onProgress(0.99, "downloading…");
  const r = await fetch(`/api/jobs/${job.id}/file`);
  if (!r.ok) throw new Error("download failed");
  const blob = await r.blob();
  onProgress(1, "done");
  const res = st.result;
  return { blob, stats: { frames: res.frames, width: res.width, height: res.height, fps: res.fps, codec: `server ${res.encoder}`, bitrateMode: "", audioMode: res.audioMode, bytes: blob.size, effectErrors: res.effectErrors } };
}
