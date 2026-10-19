import subprocess
import time
import json
import urllib.request
import os
import asyncio
import websockets

EDGE_PATH = r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
if not os.path.exists(EDGE_PATH):
    EDGE_PATH = r"C:\Program Files\Microsoft\Edge\Application\msedge.exe"

port = 9224
user_data = r"C:\Users\Almustaqbal\AppData\Local\Temp\edge_watchdog_profile"

async def test_case(name, extra_flags, user_agent=None, eval_code=None):
    print(f"\n==========================================")
    print(f"[*] Running Test Case: {name}")
    print(f"==========================================")

    cmd = [
        EDGE_PATH,
        f"--remote-debugging-port={port}",
        f"--user-data-dir={user_data}_{port}",
        "--headless=new",
        "--no-first-run",
        "--no-default-browser-check",
    ] + extra_flags + ["about:blank"]

    proc = subprocess.Popen(cmd)
    try:
        time.sleep(2)
        tabs_url = f"http://127.0.0.1:{port}/json"
        req = urllib.request.urlopen(tabs_url)
        tabs = json.loads(req.read().decode())
        ws_url = tabs[0]["webSocketDebuggerUrl"]

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

            await send("Page.enable")
            await send("Runtime.enable")
            if user_agent:
                await send("Network.setUserAgentOverride", {"userAgent": user_agent})

            target_url = "https://mohadarati.vercel.app"
            print(f"[*] Navigating to {target_url}...")
            await send("Page.navigate", {"url": target_url})

            # Check status after 3-5 seconds
            await asyncio.sleep(4)
            if eval_code:
                res = await send("Runtime.evaluate", {"expression": eval_code, "returnByValue": True})
                val = res.get("result", {}).get("value")
                print(f"[+] Evaluation Result: {val}")
                return val
    finally:
        proc.terminate()
        proc.wait()

async def main():
    # 1. Test In-App Browser detection
    iab_ua = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 Telegram-iOS/10.0"
    val1 = await test_case(
        "Telegram iOS In-App Browser Simulation",
        extra_flags=["--disable-gpu"],
        user_agent=iab_ua,
        eval_code="({ iabBarVisible: document.getElementById('in-app-browser-bar') ? window.getComputedStyle(document.getElementById('in-app-browser-bar')).display !== 'none' : false })"
    )

    # 2. Test Normal load (Clean rendering, Recovery hidden)
    val2 = await test_case(
        "Normal Desktop/Mobile Browser",
        extra_flags=["--disable-gpu"],
        eval_code="({ recoveryVisible: document.getElementById('client-recovery-card') ? window.getComputedStyle(document.getElementById('client-recovery-card')).display !== 'none' : false, fltView: !!(document.querySelector('flutter-view') || document.querySelector('flt-glass-pane')) })"
    )

    print("\n[SUMMARY OF RESULTS]:")
    print("In-App Browser detected bar:", val1)
    print("Normal Browser status:", val2)

asyncio.run(main())
