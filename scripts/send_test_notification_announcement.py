import urllib.request
import json
import base64
import sys

if hasattr(sys.stdout, 'reconfigure'):
    sys.stdout.reconfigure(encoding='utf-8')

# 1. مفتاح وقاعدة Supabase الرسمية
key = base64.b64decode('ZXlKaGJHY2lPaUpJVXpJMU5pSXNJblI1Y0NJNklrcFhWQ0o5LmV5SnBjM01pT2lKemRYQmhZbUZ6WlNJc0luSmxaaUk2SW0xeWRXSmtlbWRqYW05bWFuZHBjbXRrWm5kdklpd2ljbTlzWlNJNkltRnViMjRpTENKcFlYUWlPakUzT1RFNE1qQTROVEVzSW1WNGNDSTZNakV3TnpNNU5qZzFNWDAucy1fVW9KaVJnYi04NF81V2hyUXQwY1NtRkVDVTduczF5Q3ZrMFhHQ0FCUQ==').decode()

payload = {
    "title": "تجربة نظام الإشعارات والتفاعلات 🔔",
    "content": "تم تفعيل نظام التنبيهات الفورية والتفاعل الأكاديمي بنجاح. اضغط على الرسالة للتفاعل 👍❤️🔥 [SECTION:ALL]",
    "author_id": "ST-NUST-001630760-413",
    "author_name": "مجتبى عواد",
    "author_role": "admin",
    "department": "هندسة تقنيات الأجهزة الطبية",
    "stage": "المرحلة الرابعة",
    "category": "academic",
    "subject_name": "الأجهزة الطبية المختبرية I",
    "is_pinned": True
}

data = json.dumps(payload).encode('utf-8')
req = urllib.request.Request(
    'https://mrubdzgcjofjwirkdfwo.supabase.co/rest/v1/announcements',
    data=data,
    headers={
        'apikey': key,
        'Authorization': 'Bearer ' + key,
        'Content-Type': 'application/json',
        'Prefer': 'return=representation'
    }
)

announcement_id = None
try:
    with urllib.request.urlopen(req) as resp:
        res = json.loads(resp.read().decode('utf-8'))
        announcement_id = res[0]['id']
        print("[SUCCESS] Published announcement ID:", announcement_id)
except Exception as e:
    print("[ERROR publishing announcement]:", e)

# 2. إرسال تنبيه فوري عبر بوت تيليجرام لهاتف مجتبى مباشرة
BOT_TOKEN = base64.b64decode(b"ODc2MDAxNzUzMjpBQUhjb2NvYkQxLU1jTVpYcV9Yc2VMUmZqRHNQUWhZbUsxQQ==").decode('utf-8')
CHAT_ID = "7048397159"

tg_payload = {
    "chat_id": CHAT_ID,
    "text": (
        "🔔 <b>إشعار تجريبي من منظومة محاضراتي</b>\n\n"
        "📢 <b>تبليغ جديد:</b> تجربة نظام الإشعارات والتفاعلات 🔔\n\n"
        "تم نشر التبليغ الآن في المنظومة الأكاديمية بنجاح. افتح التطبيق لتجربة التفاعل بالضغط على الرسالة بدون وسوم أو هشتاكات!"
    ),
    "parse_mode": "HTML",
    "reply_markup": {
        "inline_keyboard": [
            [
                {"text": "📱 فتح المنصة الآن", "url": "https://mohadarati.vercel.app"}
            ]
        ]
    }
}

tg_data = json.dumps(tg_payload).encode('utf-8')
tg_req = urllib.request.Request(
    f"https://api.telegram.org/bot{BOT_TOKEN}/sendMessage",
    data=tg_data,
    headers={"Content-Type": "application/json"}
)

try:
    with urllib.request.urlopen(tg_req) as resp:
        res = json.loads(resp.read().decode('utf-8'))
        if res.get('ok'):
            print("[SUCCESS] Sent instant alert to Telegram chat ID:", CHAT_ID)
except Exception as e:
    print("[ERROR sending Telegram notification]:", e)
