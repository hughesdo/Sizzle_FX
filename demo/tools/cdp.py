"""Tiny Chrome DevTools Protocol driver for the recording browser.

The recording browser is a separate Chrome (own temp profile, full screen) started
with --remote-debugging-port=9333. Each call connects, acts, disconnects.

CLI:
  py cdp.py launch                      start the recording Chrome
  py cdp.py nav URL
  py cdp.py js "expression"             prints the JSON result
  py cdp.py key ArrowRight [repeat] [delay_s]
  py cdp.py click X Y                   fake cursor glides there, then a real CDP click
  py cdp.py type "text" [delay_s]
  py cdp.py file "css selector" PATH    set a file input (no size limit)
  py cdp.py shot out.png
"""
import asyncio, base64, json, subprocess, sys, time, urllib.request
from pathlib import Path
import aiohttp

PORT = 9333
ROOT = Path(__file__).resolve().parent.parent
CHROME = r"C:\Program Files\Google\Chrome\Application\chrome.exe"

# A visible arrow cursor, because CDP input moves no real pointer.
CURSOR_JS = r"""
(() => {
  if (window.__fc) return;
  const mk = () => {
    if (!document.body || document.getElementById('__fc')) return;
    const d = document.createElement('div');
    d.id = '__fc';
    d.innerHTML = '<svg width="28" height="28" viewBox="0 0 24 24"><path d="M3 2l7 19 2.6-7.4L20 11z" fill="#fff" stroke="#000" stroke-width="1.4" stroke-linejoin="round"/></svg>';
    Object.assign(d.style, {position:'fixed', left:'0', top:'0', zIndex:2147483647, pointerEvents:'none',
      transform:'translate(-200px,-200px)', transition:'transform .55s cubic-bezier(.4,0,.2,1)',
      filter:'drop-shadow(0 2px 3px rgba(0,0,0,.5))'});
    document.body.appendChild(d);
  };
  window.__fc = (x, y, ms) => { mk(); const d = document.getElementById('__fc');
    d.style.transition = `transform ${ms||550}ms cubic-bezier(.4,0,.2,1)`;
    d.style.transform = `translate(${x - 3}px,${y - 2}px)`; };
  window.__fcPulse = (x, y) => { const r = document.createElement('div');
    Object.assign(r.style, {position:'fixed', left:(x-18)+'px', top:(y-18)+'px', width:'36px', height:'36px',
      borderRadius:'50%', border:'3px solid #ffd54a', zIndex:2147483646, pointerEvents:'none',
      transition:'transform .45s ease-out, opacity .45s ease-out'});
    document.body.appendChild(r); requestAnimationFrame(() => { r.style.transform = 'scale(1.8)'; r.style.opacity = '0'; });
    setTimeout(() => r.remove(), 600); };
  if (document.readyState !== 'loading') mk(); else addEventListener('DOMContentLoaded', mk);
})();
"""


def launch():
    prof = ROOT / "chrome-profile"
    subprocess.Popen([CHROME, f"--remote-debugging-port={PORT}", f"--user-data-dir={prof}",
                      "--no-first-run", "--no-default-browser-check", "--start-fullscreen",
                      "--window-position=0,0", "--window-size=1920,1080",
                      "--autoplay-policy=no-user-gesture-required",
                      "--disable-features=Translate,MediaRouter", "--hide-crash-restore-bubble",
                      "about:blank"])


def page_ws():
    for _ in range(50):
        try:
            tabs = json.load(urllib.request.urlopen(f"http://127.0.0.1:{PORT}/json"))
            pages = [t for t in tabs if t["type"] == "page"]
            if pages:
                return pages[0]["webSocketDebuggerUrl"]
        except OSError:
            pass
        time.sleep(0.2)
    raise SystemExit("recording Chrome not reachable on port %d" % PORT)


class Page:
    def __init__(self):
        self.n = 0
        self.events = []

    async def __aenter__(self):
        self.s = aiohttp.ClientSession()
        self.ws = await self.s.ws_connect(page_ws(), max_msg_size=0)
        await self.send("Page.enable")
        await self.send("Runtime.enable")
        await self.send("Page.addScriptToEvaluateOnNewDocument", source=CURSOR_JS)
        await self.js(CURSOR_JS)
        return self

    async def __aexit__(self, *a):
        await self.ws.close()
        await self.s.close()

    async def send(self, method, **params):
        self.n += 1
        mid = self.n
        await self.ws.send_json({"id": mid, "method": method, "params": params})
        while True:
            msg = await self.ws.receive_json()
            if "method" in msg:
                self.events.append(msg)
            if msg.get("id") == mid:
                if "error" in msg:
                    raise RuntimeError(f"{method}: {msg['error']}")
                return msg.get("result", {})

    async def js(self, expr):
        r = await self.send("Runtime.evaluate", expression=expr, awaitPromise=True, returnByValue=True)
        if "exceptionDetails" in r:
            raise RuntimeError(r["exceptionDetails"].get("exception", {}).get("description", r["exceptionDetails"]))
        return r.get("result", {}).get("value")

    async def nav(self, url, settle=1.0):
        await self.send("Page.navigate", url=url)
        for _ in range(100):
            if await self.js("document.readyState") == "complete":
                break
            await asyncio.sleep(0.1)
        await self.js(CURSOR_JS)
        await asyncio.sleep(settle)

    async def move(self, x, y, ms=550):
        await self.js(f"window.__fc && window.__fc({x},{y},{ms})")
        await self.send("Input.dispatchMouseEvent", type="mouseMoved", x=x, y=y)
        await asyncio.sleep(ms / 1000 + 0.05)

    async def click(self, x, y, ms=550):
        await self.move(x, y, ms)
        await self.js(f"window.__fcPulse && window.__fcPulse({x},{y})")
        for t in ("mousePressed", "mouseReleased"):
            await self.send("Input.dispatchMouseEvent", type=t, x=x, y=y, button="left", clickCount=1)

    async def click_sel(self, sel, ms=550):
        r = await self.js(f"(() => {{ const e = document.querySelector({json.dumps(sel)}); if (!e) return null;"
                          f" e.scrollIntoView({{block:'nearest'}}); const b = e.getBoundingClientRect();"
                          f" return [b.x + b.width/2, b.y + b.height/2]; }})()")
        if not r:
            raise RuntimeError(f"no element {sel}")
        await self.click(round(r[0]), round(r[1]), ms)

    async def drag(self, x0, y0, x1, y1, steps=24):
        """HTML5 drag and drop: Chrome hands us the drag data, we replay it onto the target."""
        await self.move(x0, y0)
        await self.send("Input.setInterceptDrags", enabled=True)
        self.events.clear()
        await self.send("Input.dispatchMouseEvent", type="mousePressed", x=x0, y=y0, button="left", clickCount=1)
        data = None
        for i in range(1, steps + 1):
            x, y = x0 + (x1 - x0) * i / steps, y0 + (y1 - y0) * i / steps
            await self.js(f"window.__fc && window.__fc({x},{y},30)")
            await self.send("Input.dispatchMouseEvent", type="mouseMoved", x=x, y=y, button="left", buttons=1)
            for e in self.events:
                if e["method"] == "Input.dragIntercepted":
                    data = e["params"]["data"]
            if data:
                await self.send("Input.dispatchDragEvent", type="dragOver" if i > 1 else "dragEnter", x=x, y=y, data=data)
            await asyncio.sleep(0.03)
        if data:
            await self.send("Input.dispatchDragEvent", type="drop", x=x1, y=y1, data=data)
        await self.send("Input.dispatchMouseEvent", type="mouseReleased", x=x1, y=y1, button="left", clickCount=1)
        await self.send("Input.setInterceptDrags", enabled=False)
        return bool(data)

    async def wheel(self, x, y, dy):
        await self.send("Input.dispatchMouseEvent", type="mouseWheel", x=x, y=y, deltaX=0, deltaY=dy)

    async def key(self, name, repeat=1, delay=0.0):
        codes = {"ArrowRight": 39, "ArrowLeft": 37, "ArrowUp": 38, "ArrowDown": 40, "Enter": 13,
                 "Escape": 27, "Space": 32, "PageDown": 34, "PageUp": 33, "Home": 36, "End": 35,
                 "Backspace": 8, "Tab": 9, "F5": 116}
        for _ in range(repeat):
            vk = codes.get(name, 0)
            key = " " if name == "Space" else name
            code = name if name != "Space" else "Space"
            if len(name) == 1:
                key, code, vk = name, "Key" + name.upper(), ord(name.upper())
            for t in ("keyDown", "keyUp"):
                p = dict(type=t, key=key, code=code, windowsVirtualKeyCode=vk, nativeVirtualKeyCode=vk)
                if t == "keyDown" and (len(name) == 1 or name in ("Enter", "Space")):
                    p["text"] = "\r" if name == "Enter" else key
                await self.send("Input.dispatchKeyEvent", **p)
            if delay:
                await asyncio.sleep(delay)

    async def type(self, text, delay=0.06):
        for ch in text:
            await self.send("Input.insertText", text=ch)
            await asyncio.sleep(delay)

    async def file(self, sel, path):
        doc = await self.send("DOM.getDocument")
        node = await self.send("DOM.querySelector", nodeId=doc["root"]["nodeId"], selector=sel)
        await self.send("DOM.setFileInputFiles", nodeId=node["nodeId"], files=[str(Path(path).resolve())])

    async def fullscreen(self):
        tid = (await self.send("Target.getTargetInfo"))["targetInfo"]["targetId"]
        win = await self.send("Browser.getWindowForTarget", targetId=tid)
        b = await self.send("Browser.getWindowBounds", windowId=win["windowId"])
        if b["bounds"].get("windowState") != "fullscreen":
            if b["bounds"].get("windowState") != "normal":
                await self.send("Browser.setWindowBounds", windowId=win["windowId"], bounds={"windowState": "normal"})
            await self.send("Browser.setWindowBounds", windowId=win["windowId"], bounds={"windowState": "fullscreen"})
        await asyncio.sleep(0.8)

    async def shot(self, out):
        r = await self.send("Page.captureScreenshot", format="png")
        Path(out).write_bytes(base64.b64decode(r["data"]))


async def cli(argv):
    cmd, args = argv[0], argv[1:]
    if cmd == "launch":
        launch()
        page_ws()
        print("launched")
        return
    async with Page() as p:
        if cmd == "nav":
            await p.nav(args[0])
        elif cmd == "js":
            print(json.dumps(await p.js(args[0]), indent=1))
        elif cmd == "key":
            await p.key(args[0], int(args[1]) if len(args) > 1 else 1, float(args[2]) if len(args) > 2 else 0)
        elif cmd == "click":
            await p.click(int(args[0]), int(args[1]))
        elif cmd == "type":
            await p.type(args[0], float(args[1]) if len(args) > 1 else 0.06)
        elif cmd == "file":
            await p.file(args[0], args[1])
        elif cmd == "shot":
            await p.shot(args[0])
        else:
            raise SystemExit("unknown command " + cmd)

if __name__ == "__main__":
    asyncio.run(cli(sys.argv[1:]))
