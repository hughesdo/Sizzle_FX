"""Project library: named projects saved in the user's Documents folder.

  Documents/Sizzle FX/
    Projects/<name>/project.sfx.json     the timeline (hand-editable JSON) + .bak of the previous save
    Projects/<name>/masks/<id>.*          baked mask tracks (gzip R8 frames, stats, meta), so a project
                                          reopens without re-baking even if the browser evicted OPFS
    Media/<key>                           one copy of each source video, shared by projects

Set SIZZLEFX_HOME to put the library somewhere else.
"""
from __future__ import annotations

import json
import os
import re
import shutil
import sys
import time
from pathlib import Path

from fastapi import APIRouter, HTTPException, Request
from fastapi.responses import FileResponse, JSONResponse

router = APIRouter()


def _documents() -> Path:
    if sys.platform == "win32":
        try:  # the real Documents folder (may be redirected to OneDrive)
            import ctypes
            from ctypes import wintypes
            from uuid import UUID
            fid = UUID("{FDD39AD0-238F-46AF-ADB4-6C85480369C7}")  # FOLDERID_Documents

            class GUID(ctypes.Structure):
                _fields_ = [("d1", wintypes.DWORD), ("d2", wintypes.WORD), ("d3", wintypes.WORD), ("d4", ctypes.c_ubyte * 8)]
            g = GUID(fid.fields[0], fid.fields[1], fid.fields[2], (ctypes.c_ubyte * 8)(*fid.bytes[8:]))
            out = ctypes.c_wchar_p()
            if ctypes.windll.shell32.SHGetKnownFolderPath(ctypes.byref(g), 0, None, ctypes.byref(out)) == 0:
                p = Path(out.value)
                ctypes.windll.ole32.CoTaskMemFree(out)
                return p
        except Exception:
            pass
    return Path.home() / "Documents"


HOME = Path(os.environ.get("SIZZLEFX_HOME") or (_documents() / "Sizzle FX"))
PROJECTS = HOME / "Projects"
MEDIA = HOME / "Media"
PROJECT_FILE = "project.sfx.json"

_BAD = re.compile(r'[<>:"/\\|?*\x00-\x1f]')


def _clean(name: str, what: str = "name") -> str:
    n = _BAD.sub("_", name).strip().rstrip(".")
    if not n or n in (".", "..") or len(n) > 120:
        raise HTTPException(400, f"bad {what}: {name!r}")
    return n


def _project_dir(name: str) -> Path:
    return PROJECTS / _clean(name)


async def _stream_to(request: Request, dest: Path, offset: int = 0, total: int | None = None):
    """Write the request body to dest. Big files come in chunks (?offset=&total=): each chunk lands
    at its offset in dest.part, and the last one renames it into place."""
    dest.parent.mkdir(parents=True, exist_ok=True)
    tmp = dest.with_name(dest.name + ".part")
    if offset and not tmp.exists():
        # a retried LAST chunk (the client lost our reply): the file is already complete
        if total is not None and dest.is_file() and dest.stat().st_size == total:
            async for _ in request.stream():
                pass
            return total
        raise HTTPException(409, "upload chunk out of order; restart the upload from offset 0")
    with open(tmp, "r+b" if offset else "wb") as f:
        f.seek(offset)
        async for chunk in request.stream():
            f.write(chunk)
        end = f.tell()
    if total is None or end >= total:
        if total is not None and tmp.stat().st_size != total:
            raise HTTPException(400, f"upload incomplete: {tmp.stat().st_size} of {total} bytes")
        os.replace(tmp, dest)
    return end


def _summary(d: Path) -> dict | None:
    f = d / PROJECT_FILE
    if not f.is_file():
        return None
    try:
        p = json.loads(f.read_text(encoding="utf-8"))
    except Exception:
        return {"name": d.name, "broken": True, "modified": f.stat().st_mtime}
    v = p.get("video") or {}
    return {"name": d.name, "modified": f.stat().st_mtime, "video": v.get("name"), "duration": v.get("duration"),
            "segments": len(p.get("segments") or []), "masks": len(p.get("masks") or []),
            "media": p.get("media"), "hasMedia": bool(p.get("media")) and (MEDIA / str(p.get("media"))).is_file()}


@router.get("/api/projects")
def list_projects():
    PROJECTS.mkdir(parents=True, exist_ok=True)
    items = [s for d in PROJECTS.iterdir() if d.is_dir() and (s := _summary(d))]
    items.sort(key=lambda s: -s["modified"])
    return {"root": str(HOME), "projects": items}


@router.get("/api/projects/{name}")
def get_project(name: str):
    f = _project_dir(name) / PROJECT_FILE
    if not f.is_file():
        raise HTTPException(404, "no such project")
    return JSONResponse(json.loads(f.read_text(encoding="utf-8")))


@router.put("/api/projects/{name}")
async def put_project(name: str, request: Request):
    d = _project_dir(name)
    body = await request.body()
    try:
        p = json.loads(body)
        assert isinstance(p.get("segments"), list) and isinstance(p.get("lanes"), list)
    except Exception:
        raise HTTPException(400, "not a Sizzle FX project")
    d.mkdir(parents=True, exist_ok=True)
    f = d / PROJECT_FILE
    if f.is_file():
        shutil.copyfile(f, d / (PROJECT_FILE + ".bak"))
    p["name"] = d.name
    p["savedAt"] = time.strftime("%Y-%m-%d %H:%M:%S")
    tmp = d / (PROJECT_FILE + ".part")
    tmp.write_text(json.dumps(p, indent=2), encoding="utf-8")
    os.replace(tmp, f)
    # drop mask files the project no longer lists
    keep = {m.get("id") for m in p.get("masks") or []}
    md = d / "masks"
    if md.is_dir():
        for x in md.iterdir():
            if x.name.split(".")[0] not in keep:
                x.unlink(missing_ok=True)
    return {"saved": str(f), "name": d.name}


@router.delete("/api/projects/{name}")
def delete_project(name: str):
    d = _project_dir(name)
    if not d.is_dir():
        raise HTTPException(404, "no such project")
    media = (_summary(d) or {}).get("media")
    shutil.rmtree(d)
    # remove the source copy when no other project uses it
    removed_media = False
    if media and not any((s := _summary(o)) and s.get("media") == media for o in PROJECTS.iterdir() if o.is_dir()):
        (MEDIA / media).unlink(missing_ok=True)
        removed_media = True
    return {"deleted": name, "removedMedia": removed_media}


# ---- masks inside a project folder
_MASK_FILE = re.compile(r"^[\w-]+\.(bin\.gz|stats|json)$")


@router.get("/api/projects/{name}/masks")
def list_masks(name: str):
    md = _project_dir(name) / "masks"
    files = sorted(x for x in md.iterdir() if not x.name.endswith(".part")) if md.is_dir() else []
    return {"files": [x.name for x in files], "sizes": {x.name: x.stat().st_size for x in files}}


@router.put("/api/projects/{name}/masks/{file}")
async def put_mask(name: str, file: str, request: Request, offset: int = 0, total: int | None = None):
    if not _MASK_FILE.match(file):
        raise HTTPException(400, "bad mask file name")
    return {"ok": True, "end": await _stream_to(request, _project_dir(name) / "masks" / file, offset, total)}


@router.head("/api/projects/{name}/masks/{file}")
@router.get("/api/projects/{name}/masks/{file}")
def get_mask(name: str, file: str):
    f = _project_dir(name) / "masks" / file
    if not _MASK_FILE.match(file) or not f.is_file():
        raise HTTPException(404, "no such mask file")
    return FileResponse(f, media_type="application/octet-stream")


# ---- source videos
@router.head("/api/media/{key}")
@router.get("/api/media/{key}")
def get_media(key: str):
    f = MEDIA / _clean(key, "media key")
    if not f.is_file():
        raise HTTPException(404, "no such media")
    return FileResponse(f, media_type="video/mp4" if f.suffix.lower() in (".mp4", ".m4v") else "application/octet-stream")


@router.put("/api/media/{key}")
async def put_media(key: str, request: Request, offset: int = 0, total: int | None = None):
    return {"ok": True, "end": await _stream_to(request, MEDIA / _clean(key, "media key"), offset, total)}
