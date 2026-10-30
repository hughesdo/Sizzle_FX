// The ONE frame builder. Preview and export both call renderer.render(frame) with
// the same inputs, so what you see is what you export.
//
//   source -> lane 0 segment -> scope composite -> lane 1 segment -> ... -> canvas
//
// One WebGL2 context, RGBA16F ping-pong targets (RGBA8 fallback), real effect
// chaining (each segment reads the previous segment's output), per-SEGMENT
// multi-pass state (two uses of the same effect never share feedback buffers).

import { VERTEX_SRC, TEX_UNITS, HISTORY_DEPTH, buildFragment } from "./glslLoader.js";

const COMPOSITE_FS = `#version 300 es
precision highp float;
uniform sampler2D uIn, uFx, uMaskTex;
uniform vec2 uRes;
uniform float uAmount, uHasMask, uFeather, uChoke;
uniform int uScope;           // 0 whole, 1 subject, 2 background
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
}`;

const BLIT_FS = `#version 300 es
precision highp float;
uniform sampler2D uTex;
uniform vec2 uRes;
uniform float uMaskInAlpha;
uniform float uOverlay;
uniform sampler2D uMaskTex;
out vec4 fragColor;
void main(){
  vec2 uv = gl_FragCoord.xy / uRes;
  vec3 c = clamp(texture(uTex, uv).rgb, 0.0, 1.0);
  float m = texture(uMaskTex, uv).r;
  float a = uMaskInAlpha > 0.5 ? m : 1.0;
  // mask check view: subject tinted, background dimmed
  if (uOverlay > 0.5) c = mix(c * 0.3, mix(c, vec3(1.0, 0.3, 0.45), 0.35), m);
  fragColor = vec4(c, a);
}`;

function hexToRgb(h) {
  const s = String(h).replace("#", "");
  const n = parseInt(s.length === 3 ? s.split("").map((c) => c + c).join("") : s, 16);
  return [((n >> 16) & 255) / 255, ((n >> 8) & 255) / 255, (n & 255) / 255];
}

export class Renderer {
  constructor(canvas, { preserveDrawingBuffer = false } = {}) {
    this.canvas = canvas;
    const gl = canvas.getContext("webgl2", {
      alpha: false, antialias: false, depth: false, stencil: false,
      premultipliedAlpha: false, preserveDrawingBuffer, powerPreference: "high-performance",
    });
    if (!gl) throw new Error("WebGL2 is not available in this browser");
    this.gl = gl;
    this.floatOK = !!gl.getExtension("EXT_color_buffer_float");
    gl.getExtension("OES_texture_float_linear");
    this.internalFormat = this.floatOK ? gl.RGBA16F : gl.RGBA8;
    this.texType = this.floatOK ? gl.HALF_FLOAT : gl.UNSIGNED_BYTE;
    this.vao = gl.createVertexArray();
    this.programs = new Map();     // key -> {prog, uniforms, error}
    this.segState = new Map();     // segId -> {passes:{name:{read,write}}, frame}
    this.width = 0; this.height = 0;
    this.compositeProg = this._link(COMPOSITE_FS, "composite");
    this.blitProg = this._link(BLIT_FS, "blit");
    this._initStatic();
    this.historyValid = 0; this.historyHead = -1; this.lastHistoryFrame = -10;
  }

  // ---------------------------------------------------------------- resources
  _tex(w, h, { internal, format, type, filter } = {}) {
    const gl = this.gl;
    const t = gl.createTexture();
    gl.bindTexture(gl.TEXTURE_2D, t);
    gl.texImage2D(gl.TEXTURE_2D, 0, internal ?? this.internalFormat, w, h, 0, format ?? gl.RGBA, type ?? this.texType, null);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, filter ?? gl.LINEAR);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, filter ?? gl.LINEAR);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
    return t;
  }
  _target(w, h) {
    const gl = this.gl;
    const tex = this._tex(w, h);
    const fb = gl.createFramebuffer();
    gl.bindFramebuffer(gl.FRAMEBUFFER, fb);
    gl.framebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_2D, tex, 0);
    gl.clearColor(0, 0, 0, 1); gl.clear(gl.COLOR_BUFFER_BIT);
    gl.bindFramebuffer(gl.FRAMEBUFFER, null);
    return { tex, fb, w, h };
  }
  _freeTarget(t) { if (!t) return; this.gl.deleteTexture(t.tex); this.gl.deleteFramebuffer(t.fb); }

  _initStatic() {
    const gl = this.gl;
    // 512x2 audio texture (row 0 PCM, row 1 FFT), SuperTool layout
    this.fftTex = this._tex(512, 2, { internal: gl.R8, format: gl.RED, type: gl.UNSIGNED_BYTE });
    this.fftData = new Uint8Array(1024).fill(128);
    // 1x1 white mask stand-in
    this.whiteTex = this._tex(1, 1, { internal: gl.RGBA8, format: gl.RGBA, type: gl.UNSIGNED_BYTE });
    gl.bindTexture(gl.TEXTURE_2D, this.whiteTex);
    gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA8, 1, 1, 0, gl.RGBA, gl.UNSIGNED_BYTE, new Uint8Array([255, 255, 255, 255]));
    this.blackTex = this._tex(1, 1, { internal: gl.RGBA8, format: gl.RGBA, type: gl.UNSIGNED_BYTE });
    gl.bindTexture(gl.TEXTURE_2D, this.blackTex);
    gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA8, 1, 1, 0, gl.RGBA, gl.UNSIGNED_BYTE, new Uint8Array([0, 0, 0, 255]));
    this.maskTex = null;
    this.sourceTex = this._tex(2, 2, { internal: gl.RGBA8, format: gl.RGBA, type: gl.UNSIGNED_BYTE });
  }

  resize(w, h) {
    if (w === this.width && h === this.height) return;
    const gl = this.gl;
    this.width = w; this.height = h;
    this.canvas.width = w; this.canvas.height = h;
    this._freeTarget(this.chainA); this._freeTarget(this.chainB); this._freeTarget(this.fxTarget);
    this.chainA = this._target(w, h); this.chainB = this._target(w, h); this.fxTarget = this._target(w, h);
    for (const st of this.segState.values()) this._freeSegState(st);
    this.segState.clear();
    // history ring at half res, RGBA8 (rgb = source, a = mask)
    if (this.historyTex) gl.deleteTexture(this.historyTex);
    if (this.historyFb) gl.deleteFramebuffer(this.historyFb);
    this.histW = Math.max(2, Math.round(w / 2)); this.histH = Math.max(2, Math.round(h / 2));
    this.historyTex = gl.createTexture();
    gl.bindTexture(gl.TEXTURE_2D_ARRAY, this.historyTex);
    gl.texImage3D(gl.TEXTURE_2D_ARRAY, 0, gl.RGBA8, this.histW, this.histH, HISTORY_DEPTH, 0, gl.RGBA, gl.UNSIGNED_BYTE, null);
    gl.texParameteri(gl.TEXTURE_2D_ARRAY, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
    gl.texParameteri(gl.TEXTURE_2D_ARRAY, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
    gl.texParameteri(gl.TEXTURE_2D_ARRAY, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
    gl.texParameteri(gl.TEXTURE_2D_ARRAY, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
    this.historyFb = gl.createFramebuffer();
    this.historyValid = 0; this.historyHead = -1; this.lastHistoryFrame = -10;
  }

  // ---------------------------------------------------------------- programs
  _compile(type, src) {
    const gl = this.gl;
    const sh = gl.createShader(type);
    gl.shaderSource(sh, src); gl.compileShader(sh);
    if (!gl.getShaderParameter(sh, gl.COMPILE_STATUS)) {
      const log = gl.getShaderInfoLog(sh); gl.deleteShader(sh);
      throw new Error(log || "shader compile failed");
    }
    return sh;
  }
  _link(fsSrc, label) {
    const gl = this.gl;
    const vs = this._compile(gl.VERTEX_SHADER, VERTEX_SRC);
    const fs = this._compile(gl.FRAGMENT_SHADER, fsSrc);
    const prog = gl.createProgram();
    gl.attachShader(prog, vs); gl.attachShader(prog, fs); gl.linkProgram(prog);
    gl.deleteShader(vs); gl.deleteShader(fs);
    if (!gl.getProgramParameter(prog, gl.LINK_STATUS)) throw new Error(`${label}: ${gl.getProgramInfoLog(prog)}`);
    // uniform table from the linked program (so we set ints as ints, vec3 colors as vec3...)
    const uniforms = new Map();
    const n = gl.getProgramParameter(prog, gl.ACTIVE_UNIFORMS);
    for (let i = 0; i < n; i++) {
      const info = gl.getActiveUniform(prog, i);
      const name = info.name.replace(/\[0\]$/, "");
      uniforms.set(name, { loc: gl.getUniformLocation(prog, info.name), type: info.type, size: info.size });
    }
    gl.useProgram(prog);
    for (const [name, unit] of Object.entries(TEX_UNITS)) {
      const u = uniforms.get(name); if (u) gl.uniform1i(u.loc, unit);
    }
    return { prog, uniforms };
  }

  // sources: {passName: glslText}. Compiles every pass of an effect; caches by id.
  ensureEffect(effect, sources) {
    const key = effect.id;
    const have = this.programs.get(key);
    if (have && have.version === sources.__version) return have;
    if (have) for (const p of Object.values(have.passes || {})) this.gl.deleteProgram(p.prog);
    if (have) for (const t of Object.values(have.textures || {})) this.gl.deleteTexture(t);
    const entry = { version: sources.__version, passes: {}, textures: {}, error: null };
    try {
      for (const pass of effect.passes) entry.passes[pass.name] = this._link(buildFragment(sources[pass.name]), `${effect.id}/${pass.name}`);
    } catch (err) {
      entry.error = String(err.message || err);
    }
    // texture-asset channels ({texture:"assets/x.png", wrap, filter})
    const gl = this.gl;
    for (const pass of effect.passes) for (const ch of Object.values(pass.channels || {})) {
      if (!ch || typeof ch !== "object" || !ch.texture || entry.textures[ch.texture]) continue;
      const img = sources.__textures?.[ch.texture];
      if (!img) continue;
      const t = gl.createTexture();
      gl.bindTexture(gl.TEXTURE_2D, t);
      gl.pixelStorei(gl.UNPACK_FLIP_Y_WEBGL, true);
      gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA8, gl.RGBA, gl.UNSIGNED_BYTE, img);
      gl.pixelStorei(gl.UNPACK_FLIP_Y_WEBGL, false);
      const rep = ch.wrap === "repeat" ? gl.REPEAT : gl.CLAMP_TO_EDGE;
      const lin = ch.filter === "nearest" ? gl.NEAREST : gl.LINEAR;
      gl.generateMipmap(gl.TEXTURE_2D);
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, lin === gl.LINEAR ? gl.LINEAR_MIPMAP_LINEAR : gl.NEAREST);
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, lin);
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, rep);
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, rep);
      entry.textures[ch.texture] = t;
    }
    this.programs.set(key, entry);
    // a recompiled effect invalidates feedback state of segments using it
    for (const [id, st] of this.segState) if (st.effectId === key) { this._freeSegState(st); this.segState.delete(id); }
    return entry;
  }

  _freeSegState(st) { for (const p of Object.values(st.passes)) { this._freeTarget(p.read); this._freeTarget(p.write); } }

  _segStateFor(seg, effect) {
    let st = this.segState.get(seg.id);
    if (st && st.effectId !== effect.id) { this._freeSegState(st); st = null; }
    if (!st) {
      st = { effectId: effect.id, passes: {} };
      const multi = effect.passes.length > 1 || effect.passes.some((p) => Object.values(p.channels || {}).includes(p.name));
      if (multi) for (const p of effect.passes) st.passes[p.name] = { read: this._target(this.width, this.height), write: this._target(this.width, this.height) };
      this.segState.set(seg.id, st);
    }
    return st;
  }

  dropSegment(segId) { const st = this.segState.get(segId); if (st) { this._freeSegState(st); this.segState.delete(segId); } }

  // ---------------------------------------------------------------- uploads
  uploadSource(img) {
    const gl = this.gl;
    gl.bindTexture(gl.TEXTURE_2D, this.sourceTex);
    gl.pixelStorei(gl.UNPACK_FLIP_Y_WEBGL, true);
    gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA8, gl.RGBA, gl.UNSIGNED_BYTE, img);
    gl.pixelStorei(gl.UNPACK_FLIP_Y_WEBGL, false);
  }
  // masks: [{id, data(Uint8Array w*h, rows top-down), w, h, index, stats}] for this frame.
  // One R8 texture per mask track; only re-uploaded when the frame changes.
  uploadMasks(masks) {
    const gl = this.gl;
    if (!this.maskTexs) this.maskTexs = new Map();
    const live = new Set();
    for (const m of masks || []) {
      live.add(m.id);
      let e = this.maskTexs.get(m.id);
      if (!e || e.w !== m.w || e.h !== m.h) {
        if (e) gl.deleteTexture(e.tex);
        e = { tex: this._tex(m.w, m.h, { internal: gl.R8, format: gl.RED, type: gl.UNSIGNED_BYTE }), w: m.w, h: m.h, key: null };
        this.maskTexs.set(m.id, e);
      }
      const key = `${m.index}:${m.version || 0}`;
      if (e.key !== key) {
        gl.bindTexture(gl.TEXTURE_2D, e.tex);
        gl.pixelStorei(gl.UNPACK_ALIGNMENT, 1);
        gl.pixelStorei(gl.UNPACK_FLIP_Y_WEBGL, true);
        gl.texImage2D(gl.TEXTURE_2D, 0, gl.R8, m.w, m.h, 0, gl.RED, gl.UNSIGNED_BYTE, m.data);
        gl.pixelStorei(gl.UNPACK_FLIP_Y_WEBGL, false);
        e.key = key;
      }
      e.stats = m.stats;
    }
    for (const [id, e] of this.maskTexs) if (!live.has(id)) { gl.deleteTexture(e.tex); this.maskTexs.delete(id); }
  }
  _useMask(id) {
    const e = (id && this.maskTexs?.get(id)) || this.maskTexs?.get(this.defaultMaskId);
    this.maskTex = e ? e.tex : null;
    this.curStats = e ? e.stats : null;
  }
  uploadAudio(bytes) {
    const gl = this.gl;
    gl.bindTexture(gl.TEXTURE_2D, this.fftTex);
    gl.pixelStorei(gl.UNPACK_ALIGNMENT, 1);
    gl.texSubImage2D(gl.TEXTURE_2D, 0, 0, 0, 512, 2, gl.RED, gl.UNSIGNED_BYTE, bytes || this.fftData);
  }

  // ---------------------------------------------------------------- draw helpers
  _bind2D(unit, tex) { const gl = this.gl; gl.activeTexture(gl.TEXTURE0 + unit); gl.bindTexture(gl.TEXTURE_2D, tex); }
  _draw(target) {
    const gl = this.gl;
    gl.bindFramebuffer(gl.FRAMEBUFFER, target ? target.fb : null);
    gl.viewport(0, 0, this.width, this.height);
    gl.bindVertexArray(this.vao);
    gl.drawArrays(gl.TRIANGLES, 0, 3);
  }
  _set(u, name, v) {
    const e = u.get(name); if (!e) return;
    const gl = this.gl;
    switch (e.type) {
      case gl.FLOAT: gl.uniform1f(e.loc, Array.isArray(v) ? v[0] : +v || 0); break;
      case gl.INT: case gl.BOOL:
        if (e.size > 1) {
          const arr = new Int32Array(e.size);
          if (typeof v === "string") for (let i = 0; i < e.size; i++) arr[i] = i < v.length ? v.charCodeAt(i) : 0;
          gl.uniform1iv(e.loc, arr);
        } else gl.uniform1i(e.loc, Math.round(+v || 0));
        break;
      case gl.FLOAT_VEC2: gl.uniform2fv(e.loc, Array.isArray(v) ? v : [v, v]); break;
      case gl.FLOAT_VEC3: gl.uniform3fv(e.loc, typeof v === "string" ? hexToRgb(v) : v); break;
      case gl.FLOAT_VEC4: gl.uniform4fv(e.loc, typeof v === "string" ? [...hexToRgb(v), 1] : v); break;
    }
  }

  _setBuiltins(u, f, seg, local) {
    const gl = this.gl;
    const a = f.audio || {};
    const react = seg.react ?? 1;
    const e = u.get("iResolution"); if (e) gl.uniform3f(e.loc, this.width, this.height, 1);
    const cr = u.get("iChannelResolution"); if (cr) gl.uniform3fv(cr.loc, new Float32Array([this.width, this.height, 1, this.width, this.height, 1, this.width, this.height, 1, this.width, this.height, 1]));
    this._set(u, "iTime", f.time);
    this._set(u, "iTimeDelta", f.dt);
    this._set(u, "iFrame", local.frame);
    this._set(u, "iProgress", local.t);
    this._set(u, "iSampleRate", f.sampleRate || 48000);
    const md = u.get("iMouse"); if (md) gl.uniform4f(md.loc, this.width / 2, this.height / 2, 0, 0);
    const dt = u.get("iDate"); if (dt) gl.uniform4f(dt.loc, 2026, 0, 1, f.time);
    for (const [name, key] of [["uBass", "bass"], ["uLowMid", "lowmid"], ["uMid", "mid"], ["uHigh", "high"], ["uTreble", "treble"], ["uLevel", "level"], ["uKick", "kick"], ["uSnare", "snare"], ["uHat", "hat"]])
      this._set(u, name, (a[key] || 0) * react);
    this._set(u, "uBeat", a.beat || 0);
    this._set(u, "uBarPh", a.bar || 0);
    this._set(u, "uFlow", a.flow ?? f.time);
    this._set(u, "uAudio", (a[seg.audioBand || "level"] || 0) * react);
    this._set(u, "uReact", react);
    this._set(u, "uSegT", local.t);
    this._set(u, "uSegTime", local.time);
    this._set(u, "uSegDur", seg.dur);
    this._set(u, "uMix", local.amount);
    this._set(u, "uSeed", seg.seed || 0);
    this._set(u, "uHasMask", this.maskTex ? 1 : 0);
    const ms = this.maskTex ? this.curStats : null;
    const mc = u.get("uMaskCentroid"); if (mc) gl.uniform2fv(mc.loc, ms?.centroid || [0.5, 0.5]);
    const mb = u.get("uMaskBBox"); if (mb) gl.uniform4fv(mb.loc, ms?.bbox || [0, 0, 1, 1]);
    this._set(u, "uMaskArea", ms ? ms.area : 1);
    this._set(u, "iHistoryHead", Math.max(0, this.historyHead));
    this._set(u, "iHistoryLen", Math.max(1, this.historyValid));
  }

  _bindCommon() {
    const gl = this.gl;
    this._bind2D(TEX_UNITS.iAudioFFT, this.fftTex);
    this._bind2D(TEX_UNITS.iMask, this.maskTex || this.whiteTex);
    gl.activeTexture(gl.TEXTURE0 + TEX_UNITS.iHistory);
    gl.bindTexture(gl.TEXTURE_2D_ARRAY, this.historyTex);
  }

  // run every pass of one segment's effect; returns the output texture
  _runEffect(seg, effect, entry, inputTex, f, local) {
    const gl = this.gl;
    const st = this._segStateFor(seg, effect);
    const multi = Object.keys(st.passes).length > 0;
    const params = { ...defaultsOf(effect), ...(seg.params || {}) };
    // Feedback effects see iFrame = frames rendered since their buffers started,
    // so "iFrame == 0" seeding works after a seek into the middle of a segment.
    // (Export renders sequentially from frame 0, so there it equals the segment frame.)
    if (multi) {
      if (st.lastIndex === undefined || (f.index !== st.lastIndex + 1 && f.index !== st.lastIndex)) st.count = 0;
      else if (f.index === st.lastIndex + 1) st.count++;
      st.lastIndex = f.index;
    }
    let outTex = null;
    for (const pass of effect.passes) {
      const pr = entry.passes[pass.name];
      gl.useProgram(pr.prog);
      this._bindCommon();
      for (let c = 0; c < 4; c++) {
        const ch = (pass.channels || {})[`iChannel${c}`];
        let tex = this.blackTex;
        if (ch === "input") tex = inputTex;
        else if (ch === "source") tex = this.sourceTex;
        else if (ch === "mask") tex = this.maskTex || this.whiteTex;
        else if (ch && typeof ch === "object" && ch.texture) tex = entry.textures[ch.texture] || this.blackTex;
        else if (ch && st.passes[ch]) tex = st.passes[ch].read.tex;
        else if (!ch && c === 0) tex = inputTex;
        this._bind2D(c, tex);
      }
      this._setBuiltins(pr.uniforms, f, seg, local);
      if (multi) this._set(pr.uniforms, "iFrame", st.count);
      for (const [k, v] of Object.entries(params)) this._set(pr.uniforms, k, v);
      if (multi) {
        const ps = st.passes[pass.name];
        this._draw(ps.write);
        [ps.read, ps.write] = [ps.write, ps.read];
        outTex = ps.read.tex;
      } else {
        this._draw(this.fxTarget);
        outTex = this.fxTarget.tex;
      }
    }
    return outTex;
  }

  _recordHistory(frameIndex) {
    const gl = this.gl;
    if (frameIndex === this.lastHistoryFrame) return;          // re-render of the same frame
    if (frameIndex !== this.lastHistoryFrame + 1) this.historyValid = 0;  // seek: history restarts
    this.historyHead = (this.historyHead + 1) % HISTORY_DEPTH;
    this.historyValid = Math.min(HISTORY_DEPTH, this.historyValid + 1);
    this.lastHistoryFrame = frameIndex;
    gl.bindFramebuffer(gl.FRAMEBUFFER, this.historyFb);
    gl.framebufferTextureLayer(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, this.historyTex, 0, this.historyHead);
    gl.viewport(0, 0, this.histW, this.histH);
    const pr = this.blitProg;
    gl.useProgram(pr.prog);
    this._bind2D(0, this.sourceTex);
    this._bind2D(1, this.maskTex || this.whiteTex);
    gl.uniform1i(pr.uniforms.get("uTex").loc, 0);
    const mt = pr.uniforms.get("uMaskTex"); if (mt) gl.uniform1i(mt.loc, 1);
    gl.uniform2f(pr.uniforms.get("uRes").loc, this.histW, this.histH);
    const ma = pr.uniforms.get("uMaskInAlpha"); if (ma) gl.uniform1f(ma.loc, this.maskTex ? 1 : 0);
    gl.bindVertexArray(this.vao);
    gl.drawArrays(gl.TRIANGLES, 0, 3);
    gl.bindFramebuffer(gl.FRAMEBUFFER, null);
  }

  /**
   * frame = { index, time, dt, sampleRate, audio:{bass..}, fftBytes, maskStats,
   *           layers: [{seg, effect, entry, local:{t,time,frame,amount}}] (bottom lane first) }
   * Source must already be uploaded (uploadSource) for this frame.
   */
  render(frame) {
    const gl = this.gl;
    if (!this.width) return;
    this.uploadAudio(frame.fftBytes);
    this.uploadMasks(frame.masks);
    this.defaultMaskId = frame.masks?.[0]?.id || null;
    // history is recorded first (with the default mask in alpha), so
    // historyTap(uv,0) == current frame, 1 == previous...
    this._useMask(null);
    this._recordHistory(frame.index);
    let cur = this.sourceTex;
    let ping = this.chainA, pong = this.chainB;
    for (const L of frame.layers) {
      if (!L.entry || L.entry.error) continue;
      this._useMask(L.seg.maskTrackId);
      const fx = this._runEffect(L.seg, L.effect, L.entry, cur, frame, L.local);
      const pr = this.compositeProg;
      gl.useProgram(pr.prog);
      this._bind2D(0, cur); this._bind2D(1, fx); this._bind2D(2, this.maskTex || this.whiteTex);
      gl.uniform1i(pr.uniforms.get("uIn").loc, 0);
      gl.uniform1i(pr.uniforms.get("uFx").loc, 1);
      const mt = pr.uniforms.get("uMaskTex"); if (mt) gl.uniform1i(mt.loc, 2);
      gl.uniform2f(pr.uniforms.get("uRes").loc, this.width, this.height);
      gl.uniform1f(pr.uniforms.get("uAmount").loc, L.local.amount);
      const sc = pr.uniforms.get("uScope"); if (sc) gl.uniform1i(sc.loc, { whole: 0, subject: 1, background: 2 }[L.seg.scope || "whole"] ?? 0);
      const hm = pr.uniforms.get("uHasMask"); if (hm) gl.uniform1f(hm.loc, this.maskTex ? 1 : 0);
      const fe = pr.uniforms.get("uFeather"); if (fe) gl.uniform1f(fe.loc, L.seg.feather ?? 0.15);
      const ch = pr.uniforms.get("uChoke"); if (ch) gl.uniform1f(ch.loc, L.seg.choke ?? 0.5);
      this._draw(ping);
      cur = ping.tex;
      [ping, pong] = [pong, ping];
    }
    // final blit to the canvas (optionally with a mask overlay for checking a bake)
    this._useMask(frame.overlayMask || null);
    const overlay = frame.overlayMask && this.maskTex ? 1 : 0;
    const pr = this.blitProg;
    gl.useProgram(pr.prog);
    this._bind2D(0, cur);
    this._bind2D(1, this.maskTex || this.whiteTex);
    gl.uniform1i(pr.uniforms.get("uTex").loc, 0);
    const mt = pr.uniforms.get("uMaskTex"); if (mt) gl.uniform1i(mt.loc, 1);
    gl.uniform2f(pr.uniforms.get("uRes").loc, this.width, this.height);
    const ma = pr.uniforms.get("uMaskInAlpha"); if (ma) gl.uniform1f(ma.loc, 0);
    const ov = pr.uniforms.get("uOverlay"); if (ov) gl.uniform1f(ov.loc, overlay);
    this._draw(null);
  }

  /** Read the canvas back as RGBA bytes (bottom-up rows). Used by tests. */
  readPixels() {
    const gl = this.gl;
    const px = new Uint8Array(this.width * this.height * 4);
    gl.bindFramebuffer(gl.FRAMEBUFFER, null);
    gl.readPixels(0, 0, this.width, this.height, gl.RGBA, gl.UNSIGNED_BYTE, px);
    return px;
  }
}

export function defaultsOf(effect) {
  const out = {};
  for (const [k, u] of Object.entries(effect.uniforms || {})) out[k] = u.default;
  return out;
}
