"""Sizzle FX render server (Phase 5).

Runs the SAME effect files as the browser through ModernGL on the local GPU and encodes
with ffmpeg (NVENC when available, libx264 otherwise). The browser sends the video, the
project, its audio analysis and its baked mask tracks; the server renders every frame.

  .venv/Scripts/python -m uvicorn app:app --port 8790      (run from server/)
In production it also serves the built app from ../dist.
"""
from __future__ import annotations

import json
import shutil
import threading
from pathlib import Path

from fastapi import FastAPI, File, Form, HTTPException, Request, UploadFile
from fastapi.responses import FileResponse, JSONResponse
from fastapi.staticfiles import StaticFiles

import jobs
from media import FFMPEG, FFPROBE

ROOT = Path(__file__).resolve().parent.parent
app = FastAPI(title="Sizzle FX render server")

_gpu = {"checked": False, "ok": False, "renderer": "", "error": ""}


def _check_gpu():
    if _gpu["checked"]:
        return _gpu
    try:
        import moderngl
        ctx = moderngl.create_standalone_context(require=330)
        _gpu.update(ok=True, renderer=ctx.info["GL_RENDERER"])
        ctx.release()
    except Exception as err:
        _gpu.update(ok=False, error=str(err))
    _gpu["checked"] = True
    return _gpu


@app.get("/api/status")
def status():
    g = _check_gpu()
    busy = [j.public() for j in jobs.JOBS.values() if j.state in ("queued", "rendering", "encoding")]
    return {"render_ready": bool(g["ok"] and FFMPEG and FFPROBE), "gpu": g["renderer"] or g["error"],
            "ffmpeg": bool(FFMPEG), "nvenc": jobs._NVENC, "queue": len(busy)}


@app.post("/api/render")
async def render(request: Request,
                 video: UploadFile = File(...), project: str = Form(...),
                 analysis: str | None = Form(None), fft: UploadFile | None = File(None),
                 masks: str | None = Form(None), preset: str = Form("social"), encoder: str = Form("auto")):
    jid, d = jobs.new_job_dir()
    with open(d / "source", "wb") as f:
        shutil.copyfileobj(video.file, f, 4 << 20)
    (d / "project.json").write_text(project)
    if analysis:
        (d / "analysis.json").write_text(analysis)
    if fft is not None:
        (d / "fft.bin").write_bytes(await fft.read())
    if masks:
        (d / "masks.json").write_text(masks)
        form = await request.form()
        for m in json.loads(masks):
            for key, name in ((f"mask_{m['id']}", f"mask_{m['id']}.bin.gz"), (f"stats_{m['id']}", f"stats_{m['id']}.bin")):
                up = form.get(key)
                if up is None:
                    raise HTTPException(400, f"missing {key}")
                (d / name).write_bytes(await up.read())
    job = jobs.submit(jobs.Job(id=jid, dir=d, project=json.loads(project), preset=preset, encoder=encoder))
    threading.Thread(target=jobs.cleanup, daemon=True).start()
    return job.public()


@app.get("/api/jobs/{jid}")
def job_status(jid: str):
    j = jobs.JOBS.get(jid)
    if not j:
        raise HTTPException(404, "no such job")
    return j.public()


@app.delete("/api/jobs/{jid}")
def job_cancel(jid: str):
    j = jobs.JOBS.get(jid)
    if not j:
        raise HTTPException(404, "no such job")
    j.cancel = True
    return j.public()


@app.get("/api/jobs/{jid}/file")
def job_file(jid: str, name: str = "sizzlefx.mp4"):
    j = jobs.JOBS.get(jid)
    if not j or j.state != "done":
        raise HTTPException(404, "not ready")
    return FileResponse(j.dir / "out.mp4", media_type="video/mp4", filename=Path(name).name)


@app.exception_handler(Exception)
async def _err(_req, exc):
    return JSONResponse({"error": str(exc)}, status_code=500)


# production: serve the built front-end (npm run build -> dist/)
if (ROOT / "dist").exists():
    app.mount("/", StaticFiles(directory=ROOT / "dist", html=True), name="app")
