"""Assemble the Sizzle FX walkthrough (adapted from RouletteVideo/tools/build.py).

usage: py build.py   -> out/sizzle_fx_walkthrough.mp4
Captures come from shoot.py (raw/*.mkv + marks), narration from narration.py.
Long bakes are sped up with an on-screen "Nx" tag. Wherever the app was playing the
clip, the clip's own soundtrack is laid back in sync (ducked under the voice).
"""
import json, subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RAW, NAR, TMP, OUT = ROOT / "raw", ROOT / "narration", ROOT / "build", ROOT / "out"
CLIP = ROOT / "assets" / "fx_demo_clip.mp4"
RESULT = ROOT.parent / "test-media" / "_out" / "demo_result.mp4"
FPS = 30
TMP.mkdir(exist_ok=True); OUT.mkdir(exist_ok=True)
timing = json.loads((NAR / "timing.json").read_text())
ev = {p.stem: json.loads(p.read_text()) for p in RAW.glob("*.json")}


def ff(*args):
    subprocess.check_call(["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", *map(str, args)])


E = lambda s, k: ev[s][k][0] if isinstance(ev[s][k], list) else ev[s][k]

# segment: src "raw:<scene>" or "result", a..b in source seconds, speed, look (dim/blur)
SCENES = [
    dict(id="s01_title", segs=[dict(src="result", a=12.4, b=22.5, look="dim")]),
    dict(id="s02_open", segs=[dict(src="raw:s02_open", a=E("s02_open", "start") - 0.4, b=E("s02_open", "end"))]),
    dict(id="s03_drag", segs=[dict(src="raw:s03_drag", a=0.5, b=E("s03_drag", "end"))]),
    dict(id="s04_lanes", segs=[dict(src="raw:s04_lanes", a=1.6, b=E("s04_lanes", "end"))]),
    dict(id="s05_masks", segs=[
        dict(src="raw:s05_masks", a=0.5, b=E("s05_masks", "bake_start") + 2.5),
        dict(src="raw:s05_masks", a=E("s05_masks", "bake_start") + 2.5, b=E("s05_masks", "bake_done"), speed=10),
        dict(src="raw:s05_masks", a=E("s05_masks", "bake_done"), b=E("s05_masks", "end"))]),
    dict(id="s06_scope", segs=[dict(src="raw:s06_scope", a=0.5, b=E("s06_scope", "end"))]),
    dict(id="s07_body", segs=[dict(src="raw:s07_body", a=0.5, b=E("s07_body", "end"))]),
    dict(id="s08_sam", segs=[
        dict(src="raw:s08_sam", a=0.5, b=E("s08_sam", "excluded") + 1.2),
        dict(src="raw:s08_sam", a=E("s08_sam", "excluded") + 1.2, b=E("s08_sam", "track_start") + 2.5, speed=2),
        dict(src="raw:s08_sam", a=E("s08_sam", "track_start") + 2.5, b=E("s08_sam", "track_done"), speed=50),
        dict(src="raw:s08_sam", a=E("s08_sam", "track_done"), b=E("s08_sam", "end"))]),
    dict(id="s09_export", segs=[dict(src="raw:s09_export", a=0.5, b=E("s09_export", "end"))]),
    dict(id="s10_result", segs=[dict(src="result", a=12.3, b=21.6)], result_audio=True),
    dict(id="s11_outro", segs=[dict(src="result", a=0.0, b=10.0, look="blur")]),
]

# ------------------------------------------------------------------ overlays (ASS)
CODE = r"{\fnCascadia Mono\fs40\c&HE8E8E8&}"
CARDS = {
    "s01_title": [(0.4, None, "Title", r"SIZZLE {\c&H3B5DFF&}FX"),
                  (1.0, None, "Sub", r"shader effects timeline for your videos  ·  by @OneHung")],
    "s11_outro": [(0.3, None, "Title", r"SIZZLE {\c&H3B5DFF&}FX"),
                  (0.8, None, "Sub", r"129 effects  ·  person masks  ·  browser or server render"),
                  (1.4, None, "Links", CODE + r"{\fs40}start.bat   →   http://localhost:5180\N"
                   r"{\fnInter Medium\fs34\c&HB8B8B8&}this walkthrough: the {\c&HD0FF3B&}? help{\c&HB8B8B8&} button in the app")],
}
LOWER = {
    "s05_masks": (0.4, 6.0, "◐ masks  →  + auto person"),
    "s06_scope": (6.5, None, r"segment panel  →  scope: {\c&HD0FF3B&}background only"),
    "s08_sam": (0.4, 7.0, "◐ masks  →  + click to select (SAM 2)"),
    "s09_export": (9.0, None, r"render: browser gpu  ·  {\c&HD0FF3B&}server gpu (python){\c&HFFFFFF&}  ·  same effects, same picture"),
}
NO_CAPTIONS = {"s01_title", "s11_outro"}

ASS_HEAD = r"""[Script Info]
ScriptType: v4.00+
PlayResX: 1920
PlayResY: 1080
WrapStyle: 0
ScaledBorderAndShadow: yes

[V4+ Styles]
Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
Style: Cap,Inter SemiBold,44,&H00FFFFFF,&H00FFFFFF,&H00000000,&H90000000,0,0,0,0,100,100,0,0,3,14,0,2,200,200,46,1
Style: Title,Inter SemiBold,124,&H00FFFFFF,&H00FFFFFF,&H00000000,&H64000000,0,0,0,0,100,100,14,0,1,0,6,5,100,100,0,1
Style: Sub,Inter Medium,46,&H00E8E8E8,&H00FFFFFF,&H00000000,&H64000000,0,0,0,0,100,100,1,0,1,0,4,5,100,100,0,1
Style: Links,Inter Medium,42,&H00FFFFFF,&H00FFFFFF,&H00000000,&H64000000,0,0,0,0,100,100,0,0,1,0,4,2,100,100,250,1
Style: Lower,Inter SemiBold,34,&H00FFFFFF,&H00FFFFFF,&H00000000,&H50201810,0,0,0,0,100,100,0,0,3,16,0,7,60,60,60,1
Style: Speed,Inter SemiBold,40,&H003BD0FF,&H00FFFFFF,&H00000000,&H80000000,0,0,0,0,100,100,2,0,3,14,0,9,60,60,60,1

[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
"""


def ts(t):
    t = max(t, 0)
    return f"{int(t // 3600)}:{int(t % 3600 // 60):02d}:{t % 60:05.2f}"


def dialogue(a, b, style, text, fade=(250, 250)):
    return f"Dialogue: 0,{ts(a)},{ts(b)},{style},,0,0,0,,{{\\fad({fade[0]},{fade[1]})}}{text}\n"


def render_segment(seg, out, pad=0.0):
    src = RESULT if seg["src"] == "result" else RAW / (seg["src"].split(":", 1)[1] + ".mkv")
    d_in = seg["b"] - seg["a"]
    # fill 16:9 (the 1280x704 result clip is a bit wider) and force square pixels:
    # a plain scale left SAR 45:44 on the concat and players stretched it to 1964 wide
    vf = ["scale=1920:1080:force_original_aspect_ratio=increase:flags=lanczos", "crop=1920:1080", "setsar=1"]
    if seg.get("speed"):
        vf.append(f"setpts=PTS/{seg['speed']}")
    vf.append(f"fps={FPS}")
    if seg.get("look") == "dim":
        vf += ["eq=brightness=-0.25:contrast=0.9", "vignette=PI/3.2"]
    if seg.get("look") == "blur":
        vf += ["gblur=sigma=24", "eq=brightness=-0.2:saturation=1.1"]
    if pad > 0:
        vf.append(f"tpad=stop_mode=clone:stop_duration={pad:.3f}")
    vf.append("format=yuv420p")
    ff("-ss", f"{seg['a']:.3f}", "-t", f"{d_in:.3f}", "-i", src, "-vf", ",".join(vf), "-an",
       "-c:v", "h264_nvenc", "-cq", "18", "-r", FPS, out)


def main():
    t = 0.0
    parts, narr, clips, ass = [], [], [], ASS_HEAD
    for sc in SCENES:
        sid = sc["id"]
        nd = timing.get(sid, {}).get("duration", 0)
        outs = [(s["b"] - s["a"]) / s.get("speed", 1) for s in sc["segs"]]
        L = max(sum(outs), nd + 0.6)
        pad = L - sum(outs)
        local = 0.0
        for j, (s, d) in enumerate(zip(sc["segs"], outs)):
            last = j == len(sc["segs"]) - 1
            out = TMP / f"{sid}_{j}.mp4"
            render_segment(s, out, pad if last else 0.0)
            parts.append(out)
            if s.get("speed", 1) > 1.5:
                ass += dialogue(t + local, t + local + d, "Speed", f"▶▶ {s['speed']}x", (120, 120))
            # the clip's soundtrack wherever the app (or the result video) was playing
            if s["src"] == "result":
                vol = 0.95 if sc.get("result_audio") else 0.55
                clips.append(dict(file=RESULT, at=t + local, pos=s["a"], d=d + (pad if last else 0), vol=vol))
            elif not s.get("speed"):
                scene = s["src"].split(":", 1)[1]
                for k, v in ev[scene].items():
                    if not k.startswith("play_"):
                        continue
                    cap0, vt = v
                    cap1 = ev[scene].get("stop_" + k[5:], cap0 + 3)
                    x, y = max(cap0, s["a"]), min(cap1, s["b"])
                    if y - x > 0.3:
                        clips.append(dict(file=CLIP, at=t + local + (x - s["a"]), pos=vt + (x - cap0), d=y - x, vol=0.8))
            local += d
        if nd:
            narr.append((NAR / f"{sid}.wav", t + 0.2))
            if sid not in NO_CAPTIONS:
                for c in timing[sid]["captions"]:
                    ass += dialogue(t + 0.2 + c["start"], t + 0.2 + c["end"] + 0.15, "Cap", c["text"], (120, 120))
        for a, b, style, text in CARDS.get(sid, []):
            ass += dialogue(t + a, t + (b if b is not None else L - 0.2), style, text, (350, 300))
        if sid in LOWER:
            a, b, text = LOWER[sid]
            ass += dialogue(t + a, t + (b if b is not None else L - 0.2), "Lower", text)
        print(f"{sid:12s} {t:6.1f}s +{L:5.1f}s", flush=True)
        t += L
    total = t

    (TMP / "overlay.ass").write_text(ass, encoding="utf-8")
    (TMP / "concat.txt").write_text("".join(f"file '{p.as_posix()}'\n" for p in parts))
    ff("-f", "concat", "-safe", "0", "-i", TMP / "concat.txt", "-c", "copy", TMP / "video.mp4")

    # audio: narration, synced clip audio, and a quiet bed of the clip under the rest
    args, fl = [], []
    for i, (wav, at) in enumerate(narr):
        args += ["-i", wav]
        fl.append(f"[{i}:a]aresample=48000,aformat=channel_layouts=stereo,adelay={int(at * 1000)}:all=1[n{i}]")
    k = len(narr)
    for j, c in enumerate(clips):
        args += ["-ss", f"{c['pos']:.3f}", "-t", f"{c['d']:.3f}", "-i", c["file"]]
        fo = max(c["d"] - 0.3, 0)
        fl.append(f"[{k + j}:a]aresample=48000,aformat=channel_layouts=stereo,volume={c['vol']},"
                  f"afade=t=in:d=0.25,afade=t=out:st={fo:.3f}:d=0.3,adelay={int(c['at'] * 1000)}:all=1[c{j}]")
    kb = k + len(clips)
    args += ["-stream_loop", "-1", "-i", CLIP]
    fl.append(f"[{kb}:a]aresample=48000,aformat=channel_layouts=stereo,volume=0.16,atrim=0:{total:.3f}[bed]")
    fl.append("".join(f"[n{i}]" for i in range(k)) + f"amix=inputs={k}:normalize=0,apad=whole_dur={total:.3f},asplit[nar][key]")
    fl.append("".join(f"[c{j}]" for j in range(len(clips))) + f"[bed]amix=inputs={len(clips) + 1}:normalize=0[mus]")
    fl.append("[mus][key]sidechaincompress=threshold=0.015:ratio=8:attack=15:release=450:makeup=1[duck]")
    fl.append(f"[nar][duck]amix=inputs=2:normalize=0,afade=t=out:st={total - 1.5:.2f}:d=1.5,"
              f"loudnorm=I=-14:TP=-1.5:LRA=11,atrim=0:{total:.3f}[aout]")
    ff(*args, "-filter_complex", ";".join(fl), "-map", "[aout]", "-ar", 48000, "-c:a", "pcm_s16le", TMP / "audio.wav")

    out = OUT / "sizzle_fx_walkthrough.mp4"
    ass_path = (TMP / "overlay.ass").as_posix().replace(":", r"\:")
    ff("-i", TMP / "video.mp4", "-i", TMP / "audio.wav",
       "-vf", f"subtitles='{ass_path}':fontsdir='C\\:/Windows/Fonts'",
       "-c:v", "h264_nvenc", "-preset", "p6", "-rc", "vbr", "-cq", "19", "-b:v", "12M", "-maxrate", "20M",
       "-profile:v", "high", "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "192k", "-ar", 48000,
       "-movflags", "+faststart", "-shortest", out)
    print(f"done: {out}  ({total:.1f}s)")


if __name__ == "__main__":
    main()
