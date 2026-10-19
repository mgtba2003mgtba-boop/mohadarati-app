import subprocess
import time
import json
import urllib.request
import os

EDGE_PATH = r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
if not os.path.exists(EDGE_PATH):
    EDGE_PATH = r"C:\Program Files\Microsoft\Edge\Application\msedge.exe"

port = 9223
user_data = r"C:\Users\Almustaqbal\AppData\Local\Temp\edge_test_profile"

print(f"[*] Starting headless Edge on port {port}...")
proc = subprocess.Popen([
    EDGE_PATH,
    f"--remote-debugging-port={port}",
    f"--user-data-dir={user_data}",
    "--headless=new",
    "--disable-gpu",
    "--no-first-run",
    "--no-default-browser-check",
    "about:blank"
])

try:
    time.sleep(2)
    tabs_url = f"http://127.0.0.1:{port}/json"
    req = urllib.request.urlopen(tabs_url)
    tabs = json.loads(req.read().decode())
    target_tab = tabs[0]
    ws_url = target_tab["webSocketDebuggerUrl"]
    print(f"[+] Connected to WebSocket: {ws_url}")

    # Connect via websocket
    import asyncio
    import websockets

    async def run_test():
        async with websockets.connect(ws_url, max_size=50 * 1024 * 1024) as ws:
            msg_id = 1

            async def send(method, params=None):
                nonlocal msg_id
                cid = msg_id
                msg_id += 1
                payload = {"id": cid, "method": method}
                if params:
                    payload["params"] = params
                await ws.send(json.dumps(payload))
                while True:
                    resp = await ws.recv()
                    data = json.loads(resp)
                    if data.get("id") == cid:
                        return data.get("result", {})
                    elif data.get("method") == "Runtime.consoleAPICalled":
                        log_type = data["params"]["type"]
                        args = " ".join([str(arg.get("value", arg.get("description", ""))) for arg in data["params"]["args"]])
                        print(f"  [BROWSER CONSOLE {log_type}]: {args}")
                    elif data.get("method") == "Runtime.exceptionThrown":
                        print(f"  [BROWSER EXCEPTION]: {data['params']['exceptionDetails']}")

            await send("Page.enable")
            await send("Runtime.enable")
            await send("Emulation.setDeviceMetricsOverride", {
                "width": 390,
                "height": 844,
                "deviceScaleFactor": 2,
                "mobile": True
            })

            target_url = "https://mohadarati.vercel.app"
            print(f"[*] Navigating to {target_url}...")
            await send("Page.navigate", {"url": target_url})

            # Wait for load and first frame
            for sec in range(12):
                await asyncio.sleep(1)
                eval_res = await send("Runtime.evaluate", {
                    "expression": "({ preloader: !!document.getElementById('flutter-preloader'), fltView: !!(document.querySelector('flutter-view') || document.querySelector('flt-glass-pane')), body: document.body ? document.body.innerText.substring(0, 100) : '' })",
                    "returnByValue": True
                })
                val = eval_res.get("result", {}).get("value", {})
                print(f"  t+{sec+1}s: preloader={val.get('preloader')} fltView={val.get('fltView')} snippet='{val.get('body', '').strip()[:40]}'")
                if val.get("fltView"):
                    print("[+] Flutter View rendered successfully!")
                    break

            # Capture screenshot
            print("[*] Capturing screenshot...")
            shot = await send("Page.captureScreenshot", {"format": "png"})
            import base64
            with open("scripts/live_verified_screenshot.png", "wb") as f:
                f.write(base64.b64decode(shot["data"]))
            print("[SUCCESS] Screenshot saved to scripts/live_verified_screenshot.png")

    asyncio.run(run_test())

finally:
    proc.terminate()
    proc.wait()
    print("[+] Test completed cleanly.")
