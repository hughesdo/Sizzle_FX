"""Compile + render every effect with the server renderer (the GLSL 330 twin of
tools/compile-all.html).   .venv/Scripts/python compile_all.py [--json]"""
from __future__ import annotations

import json
import sys
from pathlib import Path

import numpy as np

from frames import Analysis, build_frame
from renderer import Renderer

ROOT = Path(__file__).resolve().parent.parent
PUBLIC = ROOT / "public"


def main():
    idx = json.loads((PUBLIC / "effects" / "index.json").read_text(encoding="utf-8"))
    W, H = 320, 180
    R = Renderer(W, H, PUBLIC)
    # gradient test pattern with a white block (bottom-up doesn't matter here)
    x = np.linspace(0, 1, W)[None, :, None]; y = np.linspace(0, 1, H)[:, None, None]
    img = np.concatenate([np.broadcast_to(1 - x, (H, W, 1)), np.broadcast_to(y, (H, W, 1)), np.broadcast_to(x, (H, W, 1))], axis=2)
    img[60:120, 140:180] = 1.0
    R.upload_source((img * 255).astype(np.uint8).tobytes())
    analysis = Analysis(None, None)
    results = []
    for fx in idx["effects"]:
        entry = R.ensure_effect(fx)
        row = {"id": fx["id"], "ok": entry["error"] is None, "error": (entry["error"] or "")[:300] or None}
        if row["ok"]:
            project = {"video": {"fps": 30}, "lanes": [{"id": "L1"}],
                       "segments": [{"id": "seg-" + fx["id"], "lane": "L1", "effectId": fx["id"], "start": 0, "dur": 10, "params": {}, "mix": 1}]}
            try:
                for i in range(3):
                    out = R.render(build_frame(project, time=1 + i / 30, index=30 + i, dt=1 / 30, analysis=analysis, effects={fx["id"]: fx}, mask_tracks=[]))
                px = np.frombuffer(out, np.uint8)
                row["meanLuma"] = round(float(px.mean()), 1)
                row["coverage"] = round(float((px.reshape(-1, 3).sum(1) > 12).mean()), 3)
            except Exception as err:
                row["ok"] = False; row["error"] = f"render: {err}"[:300]
        results.append(row)
    bad = [r for r in results if not r["ok"]]
    if "--json" in sys.argv:
        print(json.dumps({"total": len(results), "failed": len(bad), "results": results}, indent=1))
    else:
        print(f"{len(results) - len(bad)}/{len(results)} compiled and rendered (GLSL 330, {R.ctx.info['GL_RENDERER']})")
        for r in bad:
            print(" !", r["id"], "::", (r["error"] or "").replace("\n", " | ")[:220])
        low = [r["id"] for r in results if r["ok"] and r.get("coverage", 1) < 0.05]
        if low:
            print(" black output:", ", ".join(low))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
