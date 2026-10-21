import os
import sys
import base64
import json
import urllib.request
import mimetypes

TOKEN_B64 = "ODc2MDAxNzUzMjpBQUhjb2NvYkQxLU1jTVpYcV9Yc2VMUmZqRHNQUWhZbUsxQQ=="
BOT_TOKEN = base64.b64decode(TOKEN_B64).decode("utf-8")
CHAT_ID = "7048397159"
APK_PATH = r"build\app\outputs\flutter-apk\app-arm64-v8a-release.apk"

print(f"[*] Uploading {APK_PATH} ({os.path.getsize(APK_PATH)} bytes) to Telegram...")

# Prepare multipart/form-data
boundary = "----WebKitFormBoundary7MA4YWxkTrZu0gW"
body = []

def add_field(name, val):
    body.append(f"--{boundary}\r\n".encode("utf-8"))
    body.append(f'Content-Disposition: form-data; name="{name}"\r\n\r\n'.encode("utf-8"))
    body.append(f"{val}\r\n".encode("utf-8"))

add_field("chat_id", CHAT_ID)
add_field("caption", "🤖 تطبيق محاضراتي المحدث v1.0.9 (APK)")

# File field
body.append(f"--{boundary}\r\n".encode("utf-8"))
body.append(f'Content-Disposition: form-data; name="document"; filename="Mohadarati_v1.0.9.apk"\r\n'.encode("utf-8"))
body.append(b"Content-Type: application/vnd.android.package-archive\r\n\r\n")

with open(APK_PATH, "rb") as f:
    file_bytes = f.read()

body.append(file_bytes)
body.append(b"\r\n")
body.append(f"--{boundary}--\r\n".encode("utf-8"))

full_body = b"".join(body)

req = urllib.request.Request(
    f"https://api.telegram.org/bot{BOT_TOKEN}/sendDocument",
    data=full_body,
    headers={
        "Content-Type": f"multipart/form-data; boundary={boundary}",
        "Content-Length": str(len(full_body)),
    }
)

try:
    with urllib.request.urlopen(req, timeout=120) as resp:
        res = json.loads(resp.read().decode("utf-8"))
        if res.get("ok"):
            doc = res["result"]["document"]
            file_id = doc["file_id"]
            with open("scripts/new_apk_file_id.txt", "w", encoding="utf-8") as out:
                out.write(file_id)
            print(f"[SUCCESS] file_id: {file_id}")
except urllib.error.HTTPError as e:
    err_body = e.read().decode("utf-8")
    print(f"[!] HTTP Error {e.code}: {err_body}")
except Exception as ex:
    print(f"[!] Exception: {ex}")
