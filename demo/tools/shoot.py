"""Record the Sizzle FX walkthrough: a ddagrab capture per scene while CDP drives the
app in the separate recording Chrome (py cdp.py launch first). Event marks (seconds from
capture start) go to raw/NAME.json; "play_*" marks are [capture time, video time] so the
build can lay the clip's own audio back in sync.

usage: py shoot.py s02_open s03_drag ...     (scenes run in order, one page, state carries over)
"""
import asyncio, json, subprocess, sys, time
from pathlib import Path
from cdp import Page

ROOT = Path(__file__).resolve().parent.parent
RAW = ROOT / "raw"
APP = "http://localhost:5180/"
CLIP = ROOT / "assets" / "fx_demo_clip.mp4"


class Rec:
    def __init__(self, name):
        self.name, self.events = name, {}

    def __enter__(self):
        RAW.mkdir(exist_ok=True)
        self.p = subprocess.Popen(
            ["ffmpeg", "-hide_banner", "-loglevel", "error", "-y",
             "-f", "lavfi", "-i", "ddagrab=output_idx=0:framerate=30:draw_mouse=0",
             "-c:v", "h264_nvenc", "-preset", "p5", "-rc", "vbr", "-cq", "19", "-b:v", "0", str(RAW / f"{self.name}.mkv")],
            stdin=subprocess.PIPE)
        self.t0 = time.time()
        time.sleep(0.8)
        return self

    def now(self):
        return round(time.time() - self.t0, 3)

    def mark(self, label, value=None):
        self.events[label] = self.now() if value is None else value
        print(f"  {label} @ {self.events[label]}", flush=True)

    def __exit__(self, *a):
        self.mark("end")
        time.sleep(0.5)
        self.p.stdin.write(b"q"); self.p.stdin.flush()
        self.p.wait(timeout=60)
        (RAW / f"{self.name}.json").write_text(json.dumps(self.events, indent=1))


# ---------------------------------------------------------------- app helpers
async def rect(p, sel):
    r = await p.js(f"(() => {{ const e = document.querySelector({json.dumps(sel)}); if (!e) return null;"
                   f" const b = e.getBoundingClientRect(); return [b.x, b.y, b.width, b.height]; }})()")
    if not r:
        raise RuntimeError("no element " + sel)
    return r


async def center(p, sel):
    x, y, w, h = await rect(p, sel)
    return round(x + w / 2), round(y + h / 2)


async def click_text(p, sel, text):
    """Click the first `sel` element whose text contains `text`."""
    r = await p.js(f"(() => {{ const e = [...document.querySelectorAll({json.dumps(sel)})].find(e => e.textContent.includes({json.dumps(text)}));"
                   f" if (!e) return null; const b = e.getBoundingClientRect(); return [b.x + b.width/2, b.y + b.height/2]; }})()")
    if not r:
        raise RuntimeError(f"no {sel} with text {text}")
    await p.click(round(r[0]), round(r[1]))


async def mouse_drag(p, x0, y0, x1, y1, steps=20, dt=0.025):
    """Plain pointer drag (timeline handles, sliders): press, glide, release."""
    await p.move(x0, y0, 350)
    await p.send("Input.dispatchMouseEvent", type="mousePressed", x=x0, y=y0, button="left", clickCount=1)
    for i in range(1, steps + 1):
        x, y = x0 + (x1 - x0) * i / steps, y0 + (y1 - y0) * i / steps
        await p.js(f"window.__fc && window.__fc({x},{y},30)")
        await p.send("Input.dispatchMouseEvent", type="mouseMoved", x=x, y=y, button="left", buttons=1)
        await asyncio.sleep(dt)
    await p.send("Input.dispatchMouseEvent", type="mouseReleased", x=x1, y=y1, button="left", clickCount=1)


async def lane_point(p, lane_index, t):
    """Screen point inside lane FX{lane_index+1} at video time t."""
    return await p.js(f"(() => {{ const tl = __sfx.timeline, id = __sfx.project.lanes[{lane_index}].id;"
                      f" const row = tl._laneEl(id).getBoundingClientRect(), inner = tl.el.inner.getBoundingClientRect();"
                      f" return [Math.round(inner.left + tl.xOf({t}) + 30), Math.round(row.top + row.height / 2)]; }})()")


async def search(p, text):
    await p.click_sel(".lib-search")
    await p.js("(() => { const s = document.querySelector('.lib-search'); s.value=''; s.dispatchEvent(new Event('input')); })()")
    if text:
        await p.type(text, 0.07)
    await asyncio.sleep(0.5)


async def drop_effect(p, effect_id, lane_index, t, dur=None):
    """Drag a library card onto a lane at time t (real HTML5 drag via CDP); optionally set the length."""
    src = await center(p, f'.fx-card[data-id="{effect_id}"]')
    x, y = await lane_point(p, lane_index, t)
    # CDP drag interception loses our custom "text/x-effect" type, so: real cursor glide,
    # page-level DragEvents carrying a DataTransfer (same as the Roulette demo)
    await p.move(*src, 500)
    await p.js(f"(() => {{ window.__dt = new DataTransfer(); const c = document.querySelector('.fx-card[data-id=\"{effect_id}\"]');"
               f" c.dispatchEvent(new DragEvent('dragstart', {{bubbles:true, dataTransfer: window.__dt}})); }})()")
    steps = 24
    for i in range(1, steps + 1):
        cx, cy = src[0] + (x - src[0]) * i / steps, src[1] + (y - src[1]) * i / steps
        await p.js(f"window.__fc && window.__fc({cx},{cy},30)")
        if i > steps * 0.6:   # over the timeline: let the lane show its drop ghost
            await p.js(f"(() => {{ const e = document.elementFromPoint({cx},{cy}); e && e.dispatchEvent(new DragEvent('dragover',"
                       f" {{bubbles:true, cancelable:true, dataTransfer: window.__dt, clientX:{cx}, clientY:{cy}}})); }})()")
        await asyncio.sleep(0.03)
    ok = await p.js(f"(() => {{ const e = document.elementFromPoint({x},{y}); const o = {{bubbles:true, cancelable:true, dataTransfer: window.__dt, clientX:{x}, clientY:{y}}};"
                    f" e.dispatchEvent(new DragEvent('dragover', o)); e.dispatchEvent(new DragEvent('drop', o)); return e.className; }})()")
    await asyncio.sleep(0.5)
    seg = await p.js(f"(() => {{ const s = __sfx.project.segments.filter(s => s.effectId === {json.dumps(effect_id)}).at(-1);"
                     f" return s ? s.id : null; }})()")
    if not seg:
        raise RuntimeError(f"drop of {effect_id} failed (drag data: {ok})")
    if dur is not None:
        # snap the start exactly, then drag the right edge on screen to the wanted length
        await p.js(f"(() => {{ const s = __sfx.project.segments.find(s => s.id === '{seg}'); s.start = {t}; __sfx.timeline.refreshSeg(s); }})()")
        hx, hy, hw, hh = await rect(p, f'.seg[data-id="{seg}"] .seg-r')
        tx = await p.js(f"(() => {{ const tl = __sfx.timeline, inner = tl.el.inner.getBoundingClientRect(); return Math.round(inner.left + tl.xOf({t + dur})); }})()")
        await mouse_drag(p, round(hx + hw / 2), round(hy + hh / 2), tx - 3, round(hy + hh / 2), steps=18)
        await asyncio.sleep(0.3)
    return seg


async def seek(p, t):
    await p.js(f"(async () => {{ const v = document.querySelector('#video'); await new Promise(r => {{ v.addEventListener('seeked', r, {{once:true}}); v.currentTime = {t}; }}); }})()")


async def play_for(p, r, label, secs, start=None):
    if start is not None:
        await seek(p, start)
    await p.click_sel(".tl-play")
    await asyncio.sleep(0.25)
    vt = await p.js("document.querySelector('#video').currentTime")
    r.mark(f"play_{label}", [r.now(), vt])
    await asyncio.sleep(secs)
    await p.js("document.querySelector('#video').pause()")
    r.mark(f"stop_{label}")


async def set_select(p, label, value):
    """A select row in the segment panel, found by its label text."""
    r = await p.js(f"(() => {{ const row = [...document.querySelectorAll('.sp-row')].find(r => r.querySelector('.sp-label')?.textContent.trim() === {json.dumps(label)});"
                   f" const s = row && row.querySelector('select'); if (!s) return null; const b = s.getBoundingClientRect(); return [b.x + b.width/2, b.y + b.height/2]; }})()")
    if not r:
        raise RuntimeError("no select " + label)
    await p.click(round(r[0]), round(r[1]))
    await p.js(f"(() => {{ const row = [...document.querySelectorAll('.sp-row')].find(r => r.querySelector('.sp-label')?.textContent.trim() === {json.dumps(label)});"
               f" const s = row.querySelector('select'); s.value = {json.dumps(value)}; s.dispatchEvent(new Event('change', {{bubbles:true}})); }})()")
    await p.key("Escape")   # close the native dropdown the click opened


async def slide(p, label, frac):
    """Drag a panel slider (found by its label) to `frac` of its range."""
    r = await p.js(f"(() => {{ const row = [...document.querySelectorAll('.sp-row')].find(r => r.querySelector('.sp-label')?.textContent.trim() === {json.dumps(label)});"
                   f" const s = row && row.querySelector('input[type=range]'); if (!s) return null; const b = s.getBoundingClientRect();"
                   f" const f = (s.value - s.min) / (s.max - s.min); return [b.x, b.y + b.height/2, b.width, f]; }})()")
    if not r:
        raise RuntimeError("no slider " + label)
    x, y, w, f0 = r
    await mouse_drag(p, round(x + 6 + (w - 12) * f0), round(y), round(x + 6 + (w - 12) * frac), round(y), steps=16, dt=0.04)


async def canvas_click(p, u, v, right=False):
    x, y, w, h = await rect(p, "#preview")
    X, Y = round(x + u * w), round(y + v * h)
    if right:
        await p.move(X, Y)
        await p.js(f"window.__fcPulse && window.__fcPulse({X},{Y})")
        for t in ("mousePressed", "mouseReleased"):
            await p.send("Input.dispatchMouseEvent", type=t, x=X, y=Y, button="right", clickCount=1)
    else:
        await p.click(X, Y)


async def wait_js(p, expr, timeout=300, poll=0.25):
    t0 = time.time()
    while time.time() - t0 < timeout:
        if await p.js(expr):
            return True
        await asyncio.sleep(poll)
    raise RuntimeError("timeout waiting for " + expr)


# ---------------------------------------------------------------- scenes
async def s02_open(p, r):
    await p.nav(APP, settle=2.0)
    await p.js("localStorage.clear()")
    await p.nav(APP, settle=2.0)
    await wait_js(p, "!!(window.__sfx && __sfx.caps)")
    await p.move(960, 500, 10)
    r.mark("start")
    await asyncio.sleep(1.2)
    # intercept the chooser: a real click must NOT pop the native Windows dialog
    # (it covers the app and shows the PC's folders)
    await p.send("Page.setInterceptFileChooserDialog", enabled=True)
    await p.click_sel("#btn-open")
    await p.file("#video-input", CLIP)
    await p.send("Page.setInterceptFileChooserDialog", enabled=False)
    r.mark("opened")
    await wait_js(p, "!!__sfx.analysis", 60)
    r.mark("analysed")
    await p.move(1200, 900, 700)                # glance over the timeline
    await asyncio.sleep(2.5)
    await wait_js(p, "document.querySelectorAll('.fx-thumb.on').length > 100", 60)
    r.mark("thumbs")
    for sel in ['.fx-card:nth-child(2)', '.fx-card:nth-child(4)', '.fx-card:nth-child(6)']:
        await p.move(*(await center(p, sel)), 600)
        await asyncio.sleep(0.8)
    await p.click_sel('.lib-cat:nth-child(3)')   # Body
    await asyncio.sleep(2.0)
    await p.click_sel('.lib-cat:nth-child(1)')   # All
    await asyncio.sleep(1.5)


async def s03_drag(p, r):
    r.mark("start")
    await search(p, "kick")
    r.mark("drag")
    seg = await drop_effect(p, "kick-zoom", 0, 0.5, 4.5)
    r.mark("dropped")
    await asyncio.sleep(0.6)
    await p.click_sel(f'.seg[data-id="{seg}"] .seg-name')
    r.mark("panel")
    await asyncio.sleep(1.0)
    await slide(p, "zoom punch", 0.55)
    await asyncio.sleep(0.6)
    await set_select(p, "audio drive", "kick")
    r.mark("drive")
    await asyncio.sleep(0.8)
    await play_for(p, r, "kick", 4.5, start=0.3)


async def s04_lanes(p, r):
    r.mark("start")
    await p.js("__sfx.panel.close()")
    await search(p, "film grade")
    await drop_effect(p, "film-grade", 1, 0.0, 22.9)
    r.mark("grade")
    await search(p, "glow")
    await drop_effect(p, "glow", 2, 0.0, 6.0)
    r.mark("glow")
    await play_for(p, r, "lanes", 4.0, start=0.3)


async def s05_masks(p, r):
    r.mark("start")
    await p.click_sel("#btn-masks")
    await asyncio.sleep(1.0)
    await click_text(p, ".mask-panel button", "auto person")
    r.mark("bake_start")
    await wait_js(p, "__sfx.masks.tracks.some(t => t.provider === 'rvm' && t.filled === t.frames) && !__sfx.masks.busy", 180)
    r.mark("bake_done")
    await asyncio.sleep(1.0)
    await play_for(p, r, "overlay", 5.0, start=12.5)


async def s06_scope(p, r):
    r.mark("start")
    # overlay off, panel closed
    await p.js("(() => { const mp = __sfx.maskPanel; mp.overlay = null; mp.onOverlay(null); mp.toggle(false); })()")
    await search(p, "kaleido")
    seg = await drop_effect(p, "st-kaleidoscope-effect", 0, 12.4, 4.0)
    await p.click_sel(f'.seg[data-id="{seg}"] .seg-name')
    await asyncio.sleep(0.8)
    r.mark("scope")
    await set_select(p, "scope", "background")
    await asyncio.sleep(0.8)
    await play_for(p, r, "scope", 4.6, start=12.4)


async def s07_body(p, r):
    r.mark("start")
    await p.js("__sfx.panel.close()")
    await search(p, "rotational")
    seg = await drop_effect(p, "rotational-clone", 2, 16.5, 3.6)
    await p.js(f"(() => {{ const s = __sfx.project.segments.find(s => s.id === '{seg}'); s.params = {{tint: 2, opacity: 0.75, spread: 12}}; s.audioBand = 'kick'; __sfx.requestDraw(); }})()")
    r.mark("clone")
    await search(p, "silhouette")
    await drop_effect(p, "silhouette-echo", 0, 17.0, 5.9)
    r.mark("echo")
    await play_for(p, r, "body", 6.4, start=16.3)


async def s08_sam(p, r):
    r.mark("start")
    await seek(p, 19.2)
    await asyncio.sleep(0.6)
    await p.click_sel("#btn-masks")
    await asyncio.sleep(0.8)
    await click_text(p, ".mask-panel button", "click to select")
    await asyncio.sleep(0.8)
    r.mark("click1")
    await canvas_click(p, 0.832, 0.77)
    await wait_js(p, "!!__sfx.selectPreview && !__sfx.maskPanel.select.busy", 120)
    r.mark("selected")
    await asyncio.sleep(1.6)
    await canvas_click(p, 0.90, 0.955, right=True)
    await wait_js(p, "!__sfx.maskPanel.select.busy", 60)
    r.mark("excluded")
    await asyncio.sleep(1.4)
    for lvl in ("part", "detail", "whole"):
        await click_text(p, ".mp-levels button", lvl)
        await wait_js(p, "!__sfx.maskPanel.select.busy", 60)
        await asyncio.sleep(1.1)
    r.mark("levels")
    await click_text(p, ".mask-panel button", "track it")
    r.mark("track_start")
    await asyncio.sleep(3.0)
    await wait_js(p, "__sfx.masks.tracks.some(t => t.provider === 'sam2' && t.filled === t.frames) && !__sfx.masks.busy", 600)
    r.mark("track_done")
    await asyncio.sleep(0.8)
    await play_for(p, r, "pumpkin", 5.0, start=16.5)
    await p.js("(() => { const mp = __sfx.maskPanel; mp.overlay = null; mp.onOverlay(null); mp.toggle(false); })()")


async def s09_export(p, r):
    r.mark("start")
    await p.move(1500, 696, 600)
    await asyncio.sleep(0.5)
    await p.js("(() => { const s = document.querySelector('#render-mode'); s.value = 'browser'; s.dispatchEvent(new Event('change')); })()")
    await p.click_sel("#btn-export")
    r.mark("browser_start")
    await wait_js(p, "!__sfx.exporting && !!__sfx.lastExport", 300)
    r.mark("browser_done")
    await p.move(*(await center(p, "#download")), 600)
    await asyncio.sleep(2.0)
    # switch to the Python render server
    x, y = await center(p, "#render-mode")
    await p.click(x, y)
    await p.js("(() => { const s = document.querySelector('#render-mode'); s.value = 'server'; s.dispatchEvent(new Event('change')); })()")
    await asyncio.sleep(1.0)
    await p.js("__sfx.lastExport = null")
    await p.click_sel("#btn-export")
    r.mark("server_start")
    await wait_js(p, "!__sfx.exporting && !!__sfx.lastExport", 600)
    r.mark("server_done")
    await asyncio.sleep(2.0)
    # keep the server render for the "result" scene
    saved = await p.js("(async () => { const b = __sfx.lastExport.blob; const r = await fetch('/__dev/save?name=demo_result.mp4', {method:'POST', body:b}); return (await r.json()).saved; })()")
    r.mark("saved", saved)


SCENES = {f.__name__: f for f in (s02_open, s03_drag, s04_lanes, s05_masks, s06_scope, s07_body, s08_sam, s09_export)}


async def bring_to_front():
    async with Page() as p:
        await p.js("document.title = 'REC-WINDOW'")
    subprocess.run(["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File",
                    str(ROOT / "tools" / "focus.ps1"), "-Title", "REC-WINDOW", "-NoMaximize"], check=True)
    time.sleep(0.5)
    async with Page() as p:
        await p.fullscreen()
        print("viewport", await p.js("innerWidth + 'x' + innerHeight"))


async def main():
    await bring_to_front()
    for name in sys.argv[1:]:
        print("scene", name, flush=True)
        async with Page() as p:
            with Rec(name) as r:
                await SCENES[name](p, r)

if __name__ == "__main__":
    asyncio.run(main())
