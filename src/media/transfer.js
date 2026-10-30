// Big local transfers in 16 MB pieces. One 500+ MB request or response through the Vite dev
// proxy can stall or drop (seen with a 526 MB source video and an 840 MB server render), so
// downloads use Range requests and uploads use ?offset=&total= chunks (server/projects.py).

export const CHUNK = 16 * 1024 * 1024;

/** GET a file as a Blob via Range requests (falls back to one request if ranges aren't served). */
export async function fetchBlobChunked(url, { onProgress, type } = {}) {
  const head = await fetch(url, { method: "HEAD" });
  if (!head.ok) throw new Error(`${url}: ${head.status}`);
  const total = +head.headers.get("content-length");
  const ctype = type || head.headers.get("content-type") || "application/octet-stream";
  if (!(total > 0) || head.headers.get("accept-ranges") !== "bytes") {
    const r = await fetch(url); if (!r.ok) throw new Error(`${url}: ${r.status}`);
    return r.blob();
  }
  const parts = [];
  for (let off = 0; off < total; off += CHUNK) {
    const end = Math.min(total, off + CHUNK) - 1;
    let buf = null;
    for (let tries = 0; tries < 3 && !buf; tries++) {
      try {
        const r = await fetch(url, { headers: { range: `bytes=${off}-${end}` } });
        if (r.status === 206 || (r.status === 200 && off === 0 && end === total - 1)) buf = await r.arrayBuffer();
        else if (!r.ok) throw new Error(`${url}: ${r.status}`);
      } catch (_) { buf = null; }
    }
    if (!buf || buf.byteLength !== end - off + 1) throw new Error(`download of ${url} failed at ${(off / 1e6).toFixed(0)} MB`);
    parts.push(buf);
    onProgress?.((end + 1) / total);
  }
  return new Blob(parts, { type: ctype });
}

/** PUT a Blob/bytes in chunks. The server ignores a retried last chunk; 409 = restart from 0. */
export async function putChunked(url, body, onProgress, restarts = 1) {
  const blob = body instanceof Blob ? body : new Blob([body]);
  const total = blob.size, sep = url.includes("?") ? "&" : "?";
  for (let off = 0; off < total || (total === 0 && off === 0); off += CHUNK) {
    const part = blob.slice(off, Math.min(total, off + CHUNK));
    let r = null;
    for (let tries = 0; tries < 3; tries++) {
      try { r = await fetch(`${url}${sep}offset=${off}&total=${total}`, { method: "PUT", body: part }); if (r.ok) break; }
      catch (_) { r = null; }
    }
    if (!r) throw new Error("could not reach the local server");
    if (r.status === 409 && restarts > 0) return putChunked(url, blob, onProgress, restarts - 1);
    if (!r.ok) throw new Error(`${url}: ${r.status} ${(await r.text()).slice(0, 200)}`);
    onProgress?.(Math.min(1, (off + part.size) / Math.max(1, total)));
    if (total === 0) break;
  }
}
