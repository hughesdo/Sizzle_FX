"""ModernGL port of src/render/renderer.js (the ONE frame builder).

source -> lane 0 segment -> scope composite -> lane 1 ... -> output. Same shaders (via
contract.py), same uniform values, same per-segment feedback state, same history ring,
so a server render matches the browser preview. Images are bottom-up (GL order): the
ffmpeg decode/encode pipes flip with -vf vflip.
"""
from __future__ import annotations

import math
from pathlib import Path

import moderngl
import numpy as np

from contract import HISTORY_DEPTH, TEX_UNITS, VERTEX, build_fragment

COMPOSITE_FS = """#version 330 core
uniform sampler2D uIn, uFx, uMaskTex;
uniform vec2 uRes;
uniform float uAmount, uHasMask, uFeather, uChoke;
uniform int uScope;
out vec4 fragColor;
void main(){
  vec2 uv = gl_FragCoord.xy / uRes;
  vec4 a = texture(uIn, uv), b = texture(uFx, uv);
  float m = 1.0;
  if (uScope != 0 && uHasMask > 0.5){
    float k = texture(uMaskTex, uv).r;
    float f = max(uFeather, 0.001);
    k = smoothstep(uChoke - f, uChoke + f, k);
    m = uScope == 1 ? k : 1.0 - k;
  }
  fragColor = vec4(mix(a.rgb, b.rgb, clamp(uAmount * m, 0.0, 1.0)), 1.0);
}"""

BLIT_FS = """#version 330 core
uniform sampler2D uTex;
uniform vec2 uRes;
uniform float uMaskInAlpha;
uniform sampler2D uMaskTex;
out vec4 fragColor;
void main(){
  vec2 uv = gl_FragCoord.xy / uRes;
  vec3 c = clamp(texture(uTex, uv).rgb, 0.0, 1.0);
  float a = uMaskInAlpha > 0.5 ? texture(uMaskTex, uv).r : 1.0;
  fragColor = vec4(c, a);
}"""

GL_FLOAT, GL_INT, GL_BOOL = 0x1406, 0x1404, 0x8B56
GL_VEC2, GL_VEC3, GL_VEC4 = 0x8B50, 0x8B51, 0x8B52


def hex_rgb(h: str):
    s = str(h).lstrip("#")
    if len(s) == 3:
        s = "".join(c * 2 for c in s)
    n = int(s, 16)
    return ((n >> 16) & 255) / 255, ((n >> 8) & 255) / 255, (n & 255) / 255


def defaults_of(effect: dict) -> dict:
    return {k: u["default"] for k, u in (effect.get("uniforms") or {}).items()}


class Renderer:
    def __init__(self, width: int, height: int, effects_root: Path):
        self.ctx = moderngl.create_standalone_context(require=330)
        self.W, self.H = width, height
        self.root = effects_root
        ctx = self.ctx
        self.programs: dict[str, dict] = {}
        self.seg_state: dict[str, dict] = {}
        self.composite = self._link(COMPOSITE_FS)
        self.blit = self._link(BLIT_FS)
        self.vaos: dict[int, moderngl.VertexArray] = {}
        self.chain = [self._target(width, height), self._target(width, height)]
        self.fx_target = self._target(width, height)
        self.out_tex = ctx.texture((width, height), 4)
        self.out_fbo = ctx.framebuffer(color_attachments=[self.out_tex])
        self.source = ctx.texture((width, height), 3); self._linear(self.source)
        self.fft = ctx.texture((512, 2), 1, alignment=1); self._linear(self.fft)
        self.fft.write(np.full(1024, 128, np.uint8).tobytes())
        self.white = ctx.texture((1, 1), 4, bytes([255, 255, 255, 255]))
        self.black = ctx.texture((1, 1), 4, bytes([0, 0, 0, 255]))
        self.hw, self.hh = max(2, round(width / 2)), max(2, round(height / 2))
        self.history = ctx.texture_array((self.hw, self.hh, HISTORY_DEPTH), 4); self._linear(self.history)
        self.hist_tex = ctx.texture((self.hw, self.hh), 4)
        self.hist_fbo = ctx.framebuffer(color_attachments=[self.hist_tex])
        self.hist_valid, self.hist_head, self.last_hist = 0, -1, -10
        self.mask_texs: dict[str, dict] = {}
        self.mask_tex = None; self.cur_stats = None; self.default_mask = None

    # ------------------------------------------------------------- resources
    def _linear(self, t):
        t.filter = (moderngl.LINEAR, moderngl.LINEAR)
        t.repeat_x = False; t.repeat_y = False
        return t

    def _target(self, w, h):
        t = self._linear(self.ctx.texture((w, h), 4, dtype="f2"))
        return {"tex": t, "fbo": self.ctx.framebuffer(color_attachments=[t])}

    def _link(self, fs: str) -> dict:
        prog = self.ctx.program(vertex_shader=VERTEX, fragment_shader=fs)
        uniforms = {}
        for name in prog:
            m = prog[name]
            if isinstance(m, moderngl.Uniform):
                uniforms[name.replace("[0]", "")] = m
        for name, unit in TEX_UNITS.items():
            if name in uniforms:
                uniforms[name].value = unit
        return {"prog": prog, "u": uniforms}

    def _vao(self, prog):
        k = id(prog)
        if k not in self.vaos:
            self.vaos[k] = self.ctx.vertex_array(prog, [])
        return self.vaos[k]

    def ensure_effect(self, effect: dict) -> dict:
        key = effect["id"]
        if key in self.programs:
            return self.programs[key]
        entry = {"passes": {}, "textures": {}, "error": None}
        base = self.root / effect["path"]
        try:
            for p in effect["passes"]:
                src = (base / p["file"]).read_text(encoding="utf-8")
                entry["passes"][p["name"]] = self._link(build_fragment(src))
        except Exception as err:  # compile/link error: skip this effect, like the browser
            entry["error"] = str(err)
        for p in effect["passes"]:
            for ch in (p.get("channels") or {}).values():
                if isinstance(ch, dict) and ch.get("texture") and ch["texture"] not in entry["textures"]:
                    entry["textures"][ch["texture"]] = self._load_texture(base / ch["texture"], ch)
        self.programs[key] = entry
        return entry

    def _load_texture(self, path: Path, ch: dict):
        from PIL import Image
        try:
            img = Image.open(path).convert("RGBA").transpose(Image.FLIP_TOP_BOTTOM)
        except Exception:
            return self.black
        t = self.ctx.texture(img.size, 4, img.tobytes())
        t.build_mipmaps()
        t.filter = (moderngl.NEAREST, moderngl.NEAREST) if ch.get("filter") == "nearest" else (moderngl.LINEAR_MIPMAP_LINEAR, moderngl.LINEAR)
        rep = ch.get("wrap") == "repeat"
        t.repeat_x = rep; t.repeat_y = rep
        return t

    def _seg_state(self, seg, effect):
        st = self.seg_state.get(seg["id"])
        if st and st["effectId"] != effect["id"]:
            st = None
        if not st:
            st = {"effectId": effect["id"], "passes": {}}
            names = {p["name"] for p in effect["passes"]}
            multi = len(effect["passes"]) > 1 or any(p["name"] in (p.get("channels") or {}).values() for p in effect["passes"])
            if multi:
                for n in names:
                    st["passes"][n] = {"read": self._target(self.W, self.H), "write": self._target(self.W, self.H)}
            self.seg_state[seg["id"]] = st
        return st

    # ------------------------------------------------------------- uploads
    def upload_source(self, rgb_bottom_up: bytes):
        self.source.write(rgb_bottom_up)

    def upload_masks(self, masks: list):
        live = set()
        for m in masks:
            t = m["track"]; live.add(t.id)
            e = self.mask_texs.get(t.id)
            if not e:
                tex = self._linear(self.ctx.texture((t.width, t.height), 1, alignment=1))
                e = self.mask_texs[t.id] = {"tex": tex, "key": None}
            if e["key"] != m["index"]:
                e["tex"].write(t.frame_bottom_up(m["index"]))
                e["key"] = m["index"]
            e["stats"] = m["stats"]
        for k in [k for k in self.mask_texs if k not in live]:
            self.mask_texs.pop(k)["tex"].release()

    def _use_mask(self, mid):
        e = (mid and self.mask_texs.get(mid)) or self.mask_texs.get(self.default_mask)
        self.mask_tex = e["tex"] if e else None
        self.cur_stats = e["stats"] if e else None

    # ------------------------------------------------------------- uniforms
    def _set(self, u: dict, name: str, v):
        m = u.get(name)
        if m is None:
            return
        t = m.gl_type
        try:
            if t == GL_FLOAT:
                m.value = float(v[0] if isinstance(v, (list, tuple)) else (v or 0))
            elif t in (GL_INT, GL_BOOL):
                if m.array_length > 1:
                    s = v if isinstance(v, str) else ""
                    m.value = [ord(s[i]) if i < len(s) else 0 for i in range(m.array_length)]
                else:
                    m.value = int(round(float(v or 0)))
            elif t == GL_VEC2:
                m.value = tuple(v) if isinstance(v, (list, tuple)) else (float(v), float(v))
            elif t == GL_VEC3:
                m.value = hex_rgb(v) if isinstance(v, str) else tuple(v)
            elif t == GL_VEC4:
                m.value = (*hex_rgb(v), 1.0) if isinstance(v, str) else tuple(v)
        except Exception:
            pass

    def _set_builtins(self, u, f, seg, local):
        a = f["audio"]; react = seg.get("react", 1)
        if "iResolution" in u: u["iResolution"].value = (self.W, self.H, 1.0)
        if "iChannelResolution" in u: u["iChannelResolution"].value = [(self.W, self.H, 1.0)] * 4
        self._set(u, "iTime", f["time"]); self._set(u, "iTimeDelta", f["dt"])
        self._set(u, "iFrame", local["frame"]); self._set(u, "iProgress", local["t"])
        self._set(u, "iSampleRate", f["sampleRate"])
        if "iMouse" in u: u["iMouse"].value = (self.W / 2, self.H / 2, 0.0, 0.0)
        if "iDate" in u: u["iDate"].value = (2026.0, 0.0, 1.0, f["time"])
        for name, key in (("uBass", "bass"), ("uLowMid", "lowmid"), ("uMid", "mid"), ("uHigh", "high"), ("uTreble", "treble"),
                          ("uLevel", "level"), ("uKick", "kick"), ("uSnare", "snare"), ("uHat", "hat")):
            self._set(u, name, a.get(key, 0) * react)
        self._set(u, "uBeat", a.get("beat", 0)); self._set(u, "uBarPh", a.get("bar", 0))
        self._set(u, "uFlow", a.get("flow", f["time"]))
        self._set(u, "uAudio", a.get(seg.get("audioBand") or "level", 0) * react)
        self._set(u, "uReact", react)
        self._set(u, "uSegT", local["t"]); self._set(u, "uSegTime", local["time"]); self._set(u, "uSegDur", seg["dur"])
        self._set(u, "uMix", local["amount"]); self._set(u, "uSeed", seg.get("seed", 0))
        self._set(u, "uHasMask", 1 if self.mask_tex else 0)
        ms = self.cur_stats if self.mask_tex else None
        if "uMaskCentroid" in u: u["uMaskCentroid"].value = ms["centroid"] if ms else (0.5, 0.5)
        if "uMaskBBox" in u: u["uMaskBBox"].value = ms["bbox"] if ms else (0.0, 0.0, 1.0, 1.0)
        self._set(u, "uMaskArea", ms["area"] if ms else 1.0)
        self._set(u, "iHistoryHead", max(0, self.hist_head)); self._set(u, "iHistoryLen", max(1, self.hist_valid))

    def _bind_common(self):
        self.fft.use(TEX_UNITS["iAudioFFT"])
        (self.mask_tex or self.white).use(TEX_UNITS["iMask"])
        self.history.use(TEX_UNITS["iHistory"])

    # ------------------------------------------------------------- passes
    def _draw(self, prog, fbo):
        fbo.use()
        self._vao(prog).render(moderngl.TRIANGLES, vertices=3)

    def _run_effect(self, seg, effect, entry, input_tex, f, local):
        st = self._seg_state(seg, effect)
        multi = bool(st["passes"])
        params = {**defaults_of(effect), **(seg.get("params") or {})}
        if multi:
            last = st.get("lastIndex")
            if last is None or (f["index"] != last + 1 and f["index"] != last):
                st["count"] = 0
            elif f["index"] == last + 1:
                st["count"] += 1
            st["lastIndex"] = f["index"]
        out = None
        for p in effect["passes"]:
            pr = entry["passes"][p["name"]]
            self._bind_common()
            chans = p.get("channels") or {}
            for c in range(4):
                ch = chans.get(f"iChannel{c}")
                tex = self.black
                if ch == "input": tex = input_tex
                elif ch == "source": tex = self.source
                elif ch == "mask": tex = self.mask_tex or self.white
                elif isinstance(ch, dict) and ch.get("texture"): tex = entry["textures"].get(ch["texture"], self.black)
                elif ch and ch in st["passes"]: tex = st["passes"][ch]["read"]["tex"]
                elif not ch and c == 0: tex = input_tex
                tex.use(c)
            u = pr["u"]
            self._set_builtins(u, f, seg, local)
            if multi:
                self._set(u, "iFrame", st["count"])
            for k, v in params.items():
                self._set(u, k, v)
            if multi:
                ps = st["passes"][p["name"]]
                self._draw(pr["prog"], ps["write"]["fbo"])
                ps["read"], ps["write"] = ps["write"], ps["read"]
                out = ps["read"]["tex"]
            else:
                self._draw(pr["prog"], self.fx_target["fbo"])
                out = self.fx_target["tex"]
        return out

    def _record_history(self, index):
        if index == self.last_hist:
            return
        if index != self.last_hist + 1:
            self.hist_valid = 0
        self.hist_head = (self.hist_head + 1) % HISTORY_DEPTH
        self.hist_valid = min(HISTORY_DEPTH, self.hist_valid + 1)
        self.last_hist = index
        pr = self.blit
        self.source.use(0); (self.mask_tex or self.white).use(1)
        u = pr["u"]
        u["uTex"].value = 0
        if "uMaskTex" in u: u["uMaskTex"].value = 1
        u["uRes"].value = (float(self.hw), float(self.hh))
        if "uMaskInAlpha" in u: u["uMaskInAlpha"].value = 1.0 if self.mask_tex else 0.0
        self._draw(pr["prog"], self.hist_fbo)
        # moderngl can't attach one layer of a texture array, so copy via a small readback
        self.history.write(self.hist_fbo.read(components=4, alignment=1), viewport=(0, 0, self.hist_head, self.hw, self.hh, 1))

    def render(self, f: dict) -> bytes:
        """Render one frame; returns RGB bytes, bottom-up rows."""
        if f["fft"] is not None:
            self.fft.write(f["fft"])
        self.upload_masks(f["masks"])
        self.default_mask = f["masks"][0]["id"] if f["masks"] else None
        self._use_mask(None)
        self._record_history(f["index"])
        cur = self.source
        ping, pong = self.chain
        for L in f["layers"]:
            entry = self.ensure_effect(L["effect"])
            if entry["error"]:
                continue
            self._use_mask(L["seg"].get("maskTrackId"))
            fx = self._run_effect(L["seg"], L["effect"], entry, cur, f, L["local"])
            pr = self.composite; u = pr["u"]
            cur.use(0); fx.use(1); (self.mask_tex or self.white).use(2)
            u["uIn"].value = 0; u["uFx"].value = 1
            if "uMaskTex" in u: u["uMaskTex"].value = 2
            u["uRes"].value = (float(self.W), float(self.H))
            u["uAmount"].value = float(L["local"]["amount"])
            if "uScope" in u: u["uScope"].value = {"whole": 0, "subject": 1, "background": 2}.get(L["seg"].get("scope") or "whole", 0)
            if "uHasMask" in u: u["uHasMask"].value = 1.0 if self.mask_tex else 0.0
            if "uFeather" in u: u["uFeather"].value = float(L["seg"].get("feather", 0.15))
            if "uChoke" in u: u["uChoke"].value = float(L["seg"].get("choke", 0.5))
            self._draw(pr["prog"], ping["fbo"])
            cur = ping["tex"]
            ping, pong = pong, ping
        pr = self.blit; u = pr["u"]
        cur.use(0); self.white.use(1)
        u["uTex"].value = 0
        if "uMaskTex" in u: u["uMaskTex"].value = 1
        u["uRes"].value = (float(self.W), float(self.H))
        if "uMaskInAlpha" in u: u["uMaskInAlpha"].value = 0.0
        self._draw(pr["prog"], self.out_fbo)
        return self.out_fbo.read(components=3, alignment=1)

    def release(self):
        self.ctx.release()
