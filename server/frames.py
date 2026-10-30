"""Per-frame inputs for the renderer. Port of src/project.js buildFrame/segAmount and
src/audio/analysis.js sampleAnalysis/fftRowAt (same maths, so server == browser)."""
from __future__ import annotations

import bisect
import math

import numpy as np

SCALARS = ("bass", "lowmid", "mid", "high", "treble")


class Analysis:
    """The browser's analysis object (sent as JSON) + its 1024-byte iAudioFFT rows."""

    def __init__(self, d: dict | None, fft_rows: bytes | None):
        self.d = d
        self.fft = None; self.sample_rate = 48000
        if not d:  # video without audio
            return
        self.fps = d["fps"]; self.n = d["n"]; self.sample_rate = d.get("sampleRate", 48000)
        self.series = {k: np.asarray(d["bands"][k], dtype=np.float32) for k in SCALARS}
        for k in ("level", "kick", "snare", "hat", "flow"):
            self.series[k] = np.asarray(d[k], dtype=np.float32)
        self.beats = list(d.get("beats") or []); self.downbeats = list(d.get("downbeats") or [])
        f = d.get("fft") or {}
        self.fft_fps = f.get("fps", 100); self.fft_n = f.get("n", 0)
        self.fft = np.frombuffer(fft_rows, dtype=np.uint8).reshape(-1, 1024) if fft_rows else None

    def sample(self, t: float) -> dict:
        if not self.d:
            return {k: 0.0 for k in (*SCALARS, "level", "kick", "snare", "hat", "beat", "bar")} | {"flow": t}
        x = min(self.n - 1, max(0.0, t * self.fps))
        i = int(math.floor(x)); j = min(self.n - 1, i + 1); f = x - i
        out = {k: float(a[i] + (a[j] - a[i]) * f) for k, a in self.series.items()}

        def phase(arr):
            if not arr or t < arr[0] or t >= arr[-1]:
                return 0.0
            lo = bisect.bisect_right(arr, t) - 1
            return (t - arr[lo]) / max(1e-3, arr[lo + 1] - arr[lo])

        out["beat"] = phase(self.beats); out["bar"] = phase(self.downbeats)
        return out

    def fft_row(self, t: float) -> bytes | None:
        if self.fft is None or not len(self.fft):
            return None
        i = max(0, min(len(self.fft) - 1, round(t * self.fft_fps)))
        return self.fft[i].tobytes()


def seg_amount(seg: dict, t: float) -> float:
    if t < seg["start"] or t >= seg["start"] + seg["dur"]:
        return 0.0
    lt = t - seg["start"]
    a = seg.get("mix", 1.0)
    if seg.get("fadeIn", 0) > 0:
        a *= min(1.0, lt / seg["fadeIn"])
    if seg.get("fadeOut", 0) > 0:
        a *= min(1.0, (seg["dur"] - lt) / seg["fadeOut"])
    return max(0.0, a)


def build_frame(project: dict, *, time: float, index: int, dt: float, analysis: Analysis, effects: dict, mask_tracks: list) -> dict:
    fps = (project.get("video") or {}).get("fps") or 30
    layers = []
    for li, lane in enumerate(project["lanes"]):
        for seg in project["segments"]:
            if seg["lane"] != lane["id"]:
                continue
            amount = seg_amount(seg, time)
            if amount <= 0:
                continue
            fx = effects.get(seg["effectId"])
            if not fx:
                continue
            lt = time - seg["start"]
            layers.append({"seg": seg, "effect": fx, "lane": li,
                           "local": {"t": min(1.0, lt / seg["dur"]), "time": lt, "frame": max(0, round(lt * fps)), "amount": amount}})
    masks = []
    for t in mask_tracks:
        i = max(0, min(t.frames - 1, index))
        masks.append({"id": t.id, "track": t, "index": i, "stats": t.stats_at(i)})
    return {"index": index, "time": time, "dt": dt, "layers": layers, "masks": masks,
            "sampleRate": analysis.sample_rate if analysis.d else 48000,
            "audio": analysis.sample(time), "fft": analysis.fft_row(time)}


class MaskTrack:
    """Mask frames from the browser: gzip-free R8 bytes (frames*h*w, rows top-down) + stats."""

    STAT_N = 7

    def __init__(self, meta: dict, data: bytes, stats: bytes):
        self.id = meta["id"]; self.width = meta["width"]; self.height = meta["height"]; self.frames = meta["frames"]
        self.data = np.frombuffer(data, dtype=np.uint8).reshape(self.frames, self.height, self.width)
        self.stats = np.frombuffer(stats, dtype=np.float32).reshape(self.frames, self.STAT_N)

    def frame_bottom_up(self, i: int) -> bytes:
        return np.ascontiguousarray(self.data[i][::-1]).tobytes()

    def stats_at(self, i: int) -> dict:
        s = self.stats[i]
        return {"centroid": (float(s[0]), float(s[1])), "bbox": tuple(float(v) for v in s[2:6]), "area": float(s[6])}
