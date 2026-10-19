import subprocess, time, json, urllib.request, asyncio, websockets
port = 9228
user_data = r'C:\Users\Almustaqbal\AppData\Local\Temp\edge_test_ua_clean'
proc = subprocess.Popen([
    r'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe',
    f'--remote-debugging-port={port}',
    f'--user-data-dir={user_data}',
    '--headless=new',
    '--disable-extensions',
    'about:blank'
])
try:
    time.sleep(2)
    tabs = json.loads(urllib.request.urlopen(f'http://127.0.0.1:{port}/json').read().decode())
    ws_url = tabs[0]['webSocketDebuggerUrl']
    async def run():
        async with websockets.connect(ws_url) as ws:
            mid = 1
            async def send(method, params=None):
                nonlocal mid; cid = mid; mid += 1
                p = {'id': cid, 'method': method}
                if params: p['params'] = params
                await ws.send(json.dumps(p))
                while True:
                    d = json.loads(await ws.recv())
                    if d.get('id') == cid: return d.get('result', {})
            await send('Page.navigate', {'url': 'https://mohadarati.vercel.app'})
            await asyncio.sleep(4)
            expr = "({ url: window.location.href, title: document.title, bodyHtmlSnippet: document.body.innerHTML.substring(0, 300) })"
            res = await send('Runtime.evaluate', {'expression': expr, 'returnByValue': True})
            print(res.get('result', {}).get('value'))
    asyncio.run(run())
finally:
    proc.terminate(); proc.wait()
