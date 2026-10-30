"""Build narration audio + caption timings from scenes.json.

Each scene's lines are synthesized one sentence at a time, so caption timing is
exact. Output: narration/<scene>.wav (with a short tail) and narration/timing.json
"""
import asyncio, json, subprocess, sys
from pathlib import Path
import truststore
truststore.inject_into_ssl()
import edge_tts

ROOT = Path(__file__).resolve().parent.parent
VOICE = "en-US-AndrewNeural"
RATE = "+4%"
GAP = 0.25     # silence between sentences
TAIL = 0.6     # silence after a scene's last sentence


def dur(p):
    out = subprocess.check_output(["ffprobe", "-v", "error", "-show_entries", "format=duration",
                                   "-of", "csv=p=0", str(p)])
    return float(out)


async def main():
    scenes = json.loads((ROOT / "scenes.json").read_text(encoding="utf-8"))
    out = ROOT / "narration"
    (out / "parts").mkdir(parents=True, exist_ok=True)
    only = set(sys.argv[1:])
    timing = json.loads((out / "timing.json").read_text()) if (out / "timing.json").exists() else {}
    for sc in scenes:
        sid = sc["id"]
        if only and sid not in only:
            continue
        if not sc.get("lines"):
            continue
        parts, caps, t = [], [], 0.0
        for i, line in enumerate(sc["lines"]):
            say = line["say"] if isinstance(line, dict) else line
            cap = line.get("cap", say) if isinstance(line, dict) else line
            mp3 = out / "parts" / f"{sid}_{i:02d}.mp3"
            await edge_tts.Communicate(say, VOICE, rate=RATE).save(str(mp3))
            d = dur(mp3)
            caps.append({"start": round(t, 3), "end": round(t + d, 3), "text": cap})
            parts.append(mp3)
            t += d + GAP
        # concat with gaps -> one wav per scene
        inputs, filt = [], []
        for i, p in enumerate(parts):
            inputs += ["-i", str(p)]
            pad = GAP if i < len(parts) - 1 else TAIL
            filt.append(f"[{i}:a]aresample=48000,aformat=channel_layouts=stereo,apad=pad_dur={pad}[a{i}]")
        filt.append("".join(f"[a{i}]" for i in range(len(parts))) + f"concat=n={len(parts)}:v=0:a=1[out]")
        wav = out / f"{sid}.wav"
        subprocess.check_call(["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", *inputs,
                               "-filter_complex", ";".join(filt), "-map", "[out]", str(wav)])
        timing[sid] = {"duration": round(dur(wav), 3), "captions": caps}
        print(f"{sid}: {timing[sid]['duration']:.1f}s, {len(caps)} lines")
    (out / "timing.json").write_text(json.dumps(timing, indent=2))
    print("total", round(sum(v["duration"] for v in timing.values()), 1), "s")

asyncio.run(main())
