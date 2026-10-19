import subprocess, time, json, urllib.request, asyncio, websockets

EDGE_PATH = r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
port = 9229
user_data = r"C:\Users\Almustaqbal\AppData\Local\Temp\edge_verify_all"

async def run_scenario(name, user_agent=None, eval_script=None):
    print(f"\n--- [SCENARIO]: {name} ---")
    proc = subprocess.Popen([
        EDGE_PATH,
        f"--remote-debugging-port={port}",
        f"--user-data-dir={user_data}_{time.time()}",
        "--headless=new",
        "--disable-extensions",
        "about:blank"
    ])
    try:
        time.sleep(2)
        tabs = json.loads(urllib.request.urlopen(f"http://127.0.0.1:{port}/json").read().decode())
        ws_url = tabs[0]["webSocketDebuggerUrl"]

        async with websockets.connect(ws_url, max_size=50*1024*1024) as ws:
            mid = 1
            async def send(method, params=None):
                nonlocal mid; cid = mid; mid += 1
                p = {"id": cid, "method": method}
                if params: p["params"] = params
                await ws.send(json.dumps(p))
                while True:
                    d = json.loads(await ws.recv())
                    if d.get("id") == cid: return d.get("result", {})

            await send("Network.enable")
            if user_agent:
                await send("Network.setUserAgentOverride", {"userAgent": user_agent})

            await send("Page.navigate", {"url": "https://mohadarati.vercel.app/?_v=1792433152"})
            await asyncio.sleep(4)

            if eval_script:
                res = await send("Runtime.evaluate", {"expression": eval_script, "returnByValue": True})
                val = res.get("result", {}).get("value", res)
                print("Result:", json.dumps(val, ensure_ascii=False, default=str))
                return val
    finally:
        proc.terminate(); proc.wait()

async def main():
    # 1. Standard Browser
    r1 = await run_scenario(
        "1. Standard Chrome/Edge Browser",
        user_agent="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
        eval_script="({ barDisplay: window.getComputedStyle(document.getElementById('in-app-browser-bar')).display, recoveryDisplay: window.getComputedStyle(document.getElementById('client-recovery-card')).display, fltReady: !!(document.querySelector('flutter-view') || document.querySelector('flt-glass-pane')) })"
    )

    # 2. Telegram In-App Browser
    r2 = await run_scenario(
        "2. Telegram iOS In-App Browser",
        user_agent="Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 Telegram-iOS/10.0",
        eval_script="({ barDisplay: window.getComputedStyle(document.getElementById('in-app-browser-bar')).display, isBarVisible: window.getComputedStyle(document.getElementById('in-app-browser-bar')).display === 'flex' })"
    )

    # 3. Emergency Recovery Trigger
    r3 = await run_scenario(
        "3. WebGL Disabled / Crash Emergency Recovery",
        user_agent="Mozilla/5.0 (Windows NT 10.0; Win64; x64)",
        eval_script="""(() => {
            window.triggerEmergencyRecovery('Hardware WebGL Unavailable');
            const card = document.getElementById('client-recovery-card');
            const desc = document.getElementById('crc-desc-text');
            return {
                recoveryDisplay: window.getComputedStyle(card).display,
                descText: desc ? desc.innerText : ''
            };
        })()"""
    )

    print("\n==========================================")
    print("ALL SCENARIOS COMPLETED SUCCESSFULLY:")
    print("Scenario 1 (Normal):", r1)
    print("Scenario 2 (In-App):", r2)
    print("Scenario 3 (Recovery Card):", r3)
    print("==========================================")

asyncio.run(main())
