import os
import sys
import json
import base64
import re
import urllib.request
import urllib.error

# Set stdout to UTF-8 to prevent Windows terminal encoding issues
sys.stdout.reconfigure(encoding='utf-8')

BOT_TOKEN = "8816281220:AAFAduddee7N8mD-UNgQIgfQ1yiFaGbdHU8"
CHANNEL_ID = -1003875986734

SUPABASE_URL = "https://mrubdzgcjofjwirkdfwo.supabase.co"
SUPABASE_KEY = base64.b64decode('ZXlKaGJHY2lPaUpJVXpJMU5pSXNJblI1Y0NJNklrcFhWQ0o5LmV5SnBjM01pT2lKemRYQmhZbUZ6WlNJc0luSmxaaUk2SW0xeWRXSmtlbWRqYW05bWFuZHBjbXRrWm5kdklpd2ljbTlzWlNJNkltRnViMjRpTENKcFlYUWlPakUzT1RFNE1qQTROVEVzSW1WNGNDSTZNakV3TnpNNU5qZzFNWDAucy1fVW9KaVJnYi04NF81V2hyUXQwY1NtRkVDVTduczF5Q3ZrMFhHQ0FCUQ==').decode()

headers = {
    'apikey': SUPABASE_KEY,
    'Authorization': f'Bearer {SUPABASE_KEY}'
}

print("[*] 1. Fetching active lectures from Supabase...")
req_lec = urllib.request.Request(f"{SUPABASE_URL}/rest/v1/lectures?select=id,title,telegram_message_id,drive_url", headers=headers)
with urllib.request.urlopen(req_lec) as resp:
    lectures = json.loads(resp.read().decode())

active_telegram_msg_ids = set()

for l in lectures:
    mid = l.get('telegram_message_id')
    if mid:
        try:
            active_telegram_msg_ids.add(int(mid))
        except:
            pass
    drive_url = l.get('drive_url') or ''
    m = re.search(r'/api/(?:file|lecture)/(\d+)', drive_url)
    if m:
        active_telegram_msg_ids.add(int(m.group(1)))

print(f"[+] Active lectures: {len(lectures)}, found {len(active_telegram_msg_ids)} linked Telegram message IDs.")

print("[*] 2. Fetching active announcements & banners from Supabase...")
req_ann = urllib.request.Request(f"{SUPABASE_URL}/rest/v1/announcements?select=id,title,content,image_url", headers=headers)
with urllib.request.urlopen(req_ann) as resp:
    announcements = json.loads(resp.read().decode())

for a in announcements:
    content = a.get('content') or ''
    m = re.search(r'\[TG_MSG_ID:(\d+)\]', content)
    if m:
        active_telegram_msg_ids.add(int(m.group(1)))
    img_url = a.get('image_url') or ''
    m2 = re.search(r'/api/file/(\d+)', img_url)
    if m2:
        active_telegram_msg_ids.add(int(m2.group(1)))

print(f"[+] Total active Telegram message IDs registered in DB: {len(active_telegram_msg_ids)}")
if active_telegram_msg_ids:
    print(f"    Min ID: {min(active_telegram_msg_ids)}, Max ID: {max(active_telegram_msg_ids)}")
    print(f"    Active IDs: {sorted(list(active_telegram_msg_ids))}")

# Check what messages exist on Telegram
# In Telegram channels, messages are sequentially numbered 1, 2, 3 ...
# We can find existing messages by testing forwardMessage or copyMessage to a test/dummy or checking existence
print("\n[*] 3. Checking Telegram Channel message existence...")
max_known_id = max(active_telegram_msg_ids) if active_telegram_msg_ids else 100
search_limit = max_known_id + 30

existing_on_telegram = []
orphans = []

for mid in range(1, search_limit + 1):
    # To test if message exists without modifying it:
    # We can try to pin or edit or copy. Or we can call deleteMessage with a dry-run or copyMessage to the same channel!
    # Wait, copyMessage to same channel creates a duplicate!
    # What about getMessage? Bot API has forwardMessage.
    # What if we test copyMessage with a dummy chat, or call editMessageCaption with same/empty?
    # Actually, forwardMessage to the channel will post.
    # What about deleteMessage? If we WANT to delete orphans, we can do it!
    # Let's first test pinChatMessage / unpinChatMessage:
    # unpinChatMessage returns ok: true if unpinned, or ok: true / 400 if not pinned, but if message doesn't exist it returns:
    # "Bad Request: message to unpin not found" or "CHAT_NOT_MODIFIED"
    url = f"https://api.telegram.org/bot{BOT_TOKEN}/unpinChatMessage"
    data = json.dumps({"chat_id": CHANNEL_ID, "message_id": mid}).encode('utf-8')
    req = urllib.request.Request(url, data=data, headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req) as resp:
            # Message exists!
            existing_on_telegram.append(mid)
            if mid not in active_telegram_msg_ids:
                orphans.append(mid)
    except urllib.error.HTTPError as err:
        body = err.read().decode('utf-8')
        # Check error message:
        # If body contains "message to unpin not found" or "message to pin not found" or "message not found":
        # Let's inspect what Telegram returns:
        if "CHAT_NOT_MODIFIED" in body or "message was not unpinned" in body or "not found" not in body.lower():
            existing_on_telegram.append(mid)
            if mid not in active_telegram_msg_ids:
                orphans.append(mid)
        # else message does not exist (e.g. deleted or never sent)

print(f"\n[+] Total detected messages on Telegram channel: {len(existing_on_telegram)}")
print(f"[!] Orphan messages on Telegram (NOT in Supabase platform): {len(orphans)}")
print(f"    Orphan IDs: {orphans}")
