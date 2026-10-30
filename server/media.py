"""ffmpeg plumbing for the server renderer: probe, a decode pipe (source frames as
bottom-up RGB, i.e. GL order), and an encode pipe (H.264 High, BT.709, faststart) that
muxes the source audio (AAC-LC copied, anything else re-encoded to AAC-LC 192k)."""
from __future__ import annotations

import json
import shutil
import subprocess
from fractions import Fraction
from pathlib import Path

FFMPEG = shutil.which("ffmpeg")
FFPROBE = shutil.which("ffprobe")
NO_WINDOW = getattr(subprocess, "CREATE_NO_WINDOW", 0)

PRESETS = {
    # x264 crf / NVENC cq. "social" ~ the browser preset, "max" for archiving / re-edits
    "social": {"crf": 18, "preset": "slow", "cq": 19},
    "max": {"crf": 15, "preset": "slower", "cq": 16},
}


def probe(path: Path) -> dict:
    out = subprocess.run([FFPROBE, "-v", "error", "-print_format", "json", "-show_streams", "-show_format", str(path)],
                         capture_output=True, text=True, creationflags=NO_WINDOW, check=True).stdout
    j = json.loads(out)
    v = next(s for s in j["streams"] if s["codec_type"] == "video")
    a = next((s for s in j["streams"] if s["codec_type"] == "audio"), None)
    return {
        "width": int(v["width"]), "height": int(v["height"]),
        "color_space": v.get("color_space"), "color_range": v.get("color_range"),
        "audio": None if not a else {"codec": a.get("codec_name"), "profile": a.get("profile")},
        "duration": float(j["format"].get("duration", 0)),
    }


def fps_fraction(fps: float) -> str:
    for exact in (Fraction(24000, 1001), Fraction(30000, 1001), Fraction(60000, 1001)):
        if abs(fps - float(exact)) < 0.002:
            return f"{exact.numerator}/{exact.denominator}"
    f = Fraction(fps).limit_denominator(1001)
    return f"{f.numerator}/{f.denominator}"


def _matrix(info: dict) -> str:
    # tagged sources keep their matrix; untagged ones are treated as BT.709 like the browser does for HD
    cs = (info.get("color_space") or "").lower()
    return {"bt470bg": "bt601", "smpte170m": "bt601", "bt601": "bt601", "bt2020nc": "bt2020"}.get(cs, "bt709")


class Decoder:
    """Yields source frames as bottom-up RGB24 bytes at width x height (display size, rotation applied)."""

    def __init__(self, path: Path, width: int, height: int, info: dict, log: Path):
        self.size = width * height * 3
        vf = f"scale={width}:{height}:in_color_matrix={_matrix(info)}:in_range={'pc' if info.get('color_range') == 'pc' else 'tv'}:flags=bicubic,format=rgb24,vflip"
        self.log = open(log, "ab")
        self.p = subprocess.Popen([FFMPEG, "-v", "error", "-i", str(path), "-map", "0:v:0", "-fps_mode", "passthrough",
                                   "-vf", vf, "-f", "rawvideo", "-pix_fmt", "rgb24", "-"],
                                  stdout=subprocess.PIPE, stderr=self.log, creationflags=NO_WINDOW)

    def __iter__(self):
        while True:
            buf = self.p.stdout.read(self.size)
            if not buf or len(buf) < self.size:
                break
            yield buf

    def close(self):
        try: self.p.kill()
        except Exception: pass
        self.log.close()


class Encoder:
    def __init__(self, out: Path, source: Path, width: int, height: int, fps: float, info: dict, preset: str, encoder: str, log: Path):
        P = PRESETS.get(preset, PRESETS["social"])
        a = info.get("audio")
        if a and a["codec"] == "aac" and (a.get("profile") or "").upper() == "LC":
            acodec, self.audio_mode = ["-c:a", "copy"], "copy"
        elif a:
            acodec, self.audio_mode = ["-c:a", "aac", "-b:a", "192k", "-ar", "48000"], "encode"
        else:
            acodec, self.audio_mode = [], "none"
        if encoder == "nvenc":
            vcodec = ["-c:v", "h264_nvenc", "-preset", "p7", "-rc", "vbr", "-cq", str(P["cq"]), "-b:v", "0", "-profile:v", "high"]
        else:
            vcodec = ["-c:v", "libx264", "-crf", str(P["crf"]), "-preset", P["preset"], "-profile:v", "high"]
        self.encoder = encoder
        self.log = open(log, "ab")
        cmd = [FFMPEG, "-y", "-v", "error",
               "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", f"{width}x{height}", "-r", fps_fraction(fps), "-i", "-",
               "-i", str(source), "-map", "0:v:0", "-map", "1:a:0?",
               "-vf", "vflip,scale=out_color_matrix=bt709:out_range=tv:flags=bicubic,format=yuv420p",
               *vcodec, "-colorspace", "bt709", "-color_primaries", "bt709", "-color_trc", "bt709", "-color_range", "tv",
               # NVENC ignores the flags above for primaries/transfer; write the VUI directly
               "-bsf:v", "h264_metadata=colour_primaries=1:transfer_characteristics=1:matrix_coefficients=1:video_full_range_flag=0",
               *acodec, "-movflags", "+faststart", str(out)]
        self.p = subprocess.Popen(cmd, stdin=subprocess.PIPE, stderr=self.log, creationflags=NO_WINDOW)

    def write(self, rgb_bottom_up: bytes):
        self.p.stdin.write(rgb_bottom_up)

    def finish(self) -> int:
        try: self.p.stdin.close()
        except Exception: pass
        rc = self.p.wait()
        self.log.close()
        return rc

    def kill(self):
        try: self.p.kill()
        except Exception: pass
        self.log.close()


def nvenc_available() -> bool:
    if not FFMPEG:
        return False
    try:
        r = subprocess.run([FFMPEG, "-v", "error", "-f", "lavfi", "-i", "color=c=black:s=256x256:d=0.1", "-c:v", "h264_nvenc", "-f", "null", "-"],
                           capture_output=True, timeout=20, creationflags=NO_WINDOW)
        return r.returncode == 0
    except Exception:
        return False
