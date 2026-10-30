"""Render jobs: a single-lane queue (one GPU) running on a worker thread, like Sizzle's.
The ModernGL context is created inside the worker thread, per job."""
from __future__ import annotations

import gzip
import json
import queue
import shutil
import threading
import time
import traceback
import uuid
from dataclasses import dataclass, field
from pathlib import Path

from frames import Analysis, MaskTrack, build_frame
from media import Decoder, Encoder, nvenc_available, probe

ROOT = Path(__file__).resolve().parent.parent
PUBLIC = ROOT / "public"
WORK = Path(__file__).resolve().parent / "_work"


@dataclass
class Job:
    id: str
    dir: Path
    project: dict
    preset: str = "social"
    encoder: str = "auto"
    state: str = "queued"          # queued | rendering | encoding | done | error | cancelled
    frame: int = 0
    total: int = 0
    fps: float = 0.0
    message: str = ""
    result: dict = field(default_factory=dict)
    created: float = field(default_factory=time.time)
    cancel: bool = False

    def public(self) -> dict:
        return {"id": self.id, "state": self.state, "frame": self.frame, "total": self.total, "fps": round(self.fps, 1),
                "message": self.message, "result": self.result, "position": position(self.id)}


JOBS: dict[str, Job] = {}
_Q: "queue.Queue[str]" = queue.Queue()
_NVENC: bool | None = None


def position(job_id: str) -> int:
    ids = [j.id for j in sorted(JOBS.values(), key=lambda j: j.created) if j.state == "queued"]
    return ids.index(job_id) if job_id in ids else -1


def submit(job: Job) -> Job:
    JOBS[job.id] = job
    _Q.put(job.id)
    return job


def new_job_dir() -> tuple[str, Path]:
    jid = uuid.uuid4().hex[:12]
    d = WORK / jid
    d.mkdir(parents=True, exist_ok=True)
    return jid, d


def _registry() -> dict:
    idx = json.loads((PUBLIC / "effects" / "index.json").read_text(encoding="utf-8"))
    return {e["id"]: e for e in idx["effects"]}


def _load_masks(job: Job) -> list[MaskTrack]:
    metas = json.loads((job.dir / "masks.json").read_text()) if (job.dir / "masks.json").exists() else []
    out = []
    for m in metas:
        data = gzip.decompress((job.dir / f"mask_{m['id']}.bin.gz").read_bytes())
        stats = (job.dir / f"stats_{m['id']}.bin").read_bytes()
        out.append(MaskTrack(m, data, stats))
    return out


def _run(job: Job):
    from renderer import Renderer  # imported here: GL context must live on this thread
    global _NVENC
    p = job.project
    v = p["video"]
    src = job.dir / "source"
    info = probe(src)
    W, H = int(v["width"]) - int(v["width"]) % 2, int(v["height"]) - int(v["height"]) % 2
    fps = float(v["fps"])
    job.total = int(v.get("frames") or round(info["duration"] * fps))
    a_path = job.dir / "analysis.json"
    analysis = Analysis(json.loads(a_path.read_text()) if a_path.exists() else None,
                        (job.dir / "fft.bin").read_bytes() if (job.dir / "fft.bin").exists() else None)
    masks = _load_masks(job)
    effects = _registry()
    missing = sorted({s["effectId"] for s in p["segments"]} - set(effects))
    if missing:
        job.message = "unknown effects skipped: " + ", ".join(missing)

    encoder = job.encoder
    if encoder == "auto":
        if _NVENC is None:
            _NVENC = nvenc_available()
        encoder = "nvenc" if _NVENC else "x264"

    out = job.dir / "out.mp4"
    R = Renderer(W, H, PUBLIC)
    dec = Decoder(src, W, H, info, job.dir / "ffmpeg_decode.log")
    enc = Encoder(out, src, W, H, fps, info, job.preset, encoder, job.dir / "ffmpeg_encode.log")
    job.state = "rendering"
    t0 = time.perf_counter()
    try:
        for i, rgb in enumerate(dec):
            if job.cancel:
                raise RuntimeError("cancelled")
            t = i / fps
            R.upload_source(rgb)
            frame = build_frame(p, time=t, index=i, dt=1 / fps, analysis=analysis, effects=effects, mask_tracks=masks)
            enc.write(R.render(frame))
            job.frame = i + 1
            job.fps = job.frame / max(1e-6, time.perf_counter() - t0)
        job.state = "encoding"
        rc = enc.finish()
        if rc != 0:
            raise RuntimeError(f"ffmpeg encode failed ({rc}); see {enc.log.name}")
    except BrokenPipeError:
        enc.kill()
        raise RuntimeError("ffmpeg encoder closed early; see ffmpeg_encode.log")
    except Exception:
        enc.kill()
        raise
    finally:
        dec.close()
        R.release()
    errors = {k: v["error"] for k, v in R.programs.items() if v["error"]}
    job.result = {"frames": job.frame, "width": W, "height": H, "fps": fps, "encoder": encoder, "audioMode": enc.audio_mode,
                  "bytes": out.stat().st_size, "seconds": round(time.perf_counter() - t0, 1), "effectErrors": errors}


def _worker():
    while True:
        jid = _Q.get()
        job = JOBS.get(jid)
        if not job or job.cancel:
            if job: job.state = "cancelled"
            continue
        try:
            _run(job)
            job.state = "done"
        except Exception as err:
            if job.cancel:
                job.state, job.message = "cancelled", "cancelled"
            else:
                job.state, job.message = "error", str(err)
                (job.dir / "error.txt").write_text(traceback.format_exc())
                # NVENC can fail on some drivers: retry once with x264
                if job.encoder == "auto" and "encode failed" in str(err):
                    global _NVENC
                    _NVENC = False
                    job.state, job.message, job.frame = "queued", "NVENC failed, retrying with x264", 0
                    _Q.put(job.id)


def cleanup(max_age_s: float = 6 * 3600):
    now = time.time()
    for j in list(JOBS.values()):
        if now - j.created > max_age_s and j.state in ("done", "error", "cancelled"):
            shutil.rmtree(j.dir, ignore_errors=True)
            JOBS.pop(j.id, None)


threading.Thread(target=_worker, daemon=True, name="render-worker").start()
