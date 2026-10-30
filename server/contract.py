"""Shader contract for the server renderer.

Everything comes from server/contract.json, which scripts/export-contract.mjs generates
from src/render/glslLoader.js, so browser and server wrap effects identically.
"""
from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent
_C = json.loads((ROOT / "contract.json").read_text(encoding="utf-8"))

VERTEX = _C["vertex"]
PREAMBLE = _C["preamble"]
HELPERS = _C["helpers"]
TEX_UNITS: dict[str, int] = _C["texUnits"]
HISTORY_DEPTH: int = _C["historyDepth"]


def _flags(js: str) -> int:
    return re.M if "m" in js else 0


def _sub(rule: dict, s: str) -> str:
    # JS "g" = replace all; without it JS replaces the first match only
    return re.sub(rule["pattern"], rule["replace"], s, count=0 if "g" in rule["flags"] else 1, flags=_flags(rule["flags"]))


def build_fragment(source: str) -> str:
    s = source
    desktop_rule = next(r for r in _C["stripRules"] if r.get("id") == "desktop")
    desktop = re.search(desktop_rule["pattern"], s, re.M) is not None
    for r in _C["stripRules"]:
        s = _sub(r, s)
    if desktop:
        s = _sub(_C["fragCoordRule"], s)
    has_main_image = re.search(_C["mainImageRe"], s) is not None
    has_main = re.search(_C["mainRe"], s) is not None
    out = PREAMBLE + HELPERS + "\n#line 1\n" + s + "\n"
    if has_main_image and not has_main:
        out += _C["mainWrapper"]
    return out


def self_check() -> None:
    got = build_fragment(_C["sample"]["source"])
    if got != _C["sample"]["expected"]:
        raise RuntimeError("server/contract.py disagrees with glslLoader.js; rerun `npm run contract`")


self_check()
