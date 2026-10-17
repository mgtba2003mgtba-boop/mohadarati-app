import urllib.request
import json
import base64
import sys

sys.stdout.reconfigure(encoding='utf-8')

key = base64.b64decode('ZXlKaGJHY2lPaUpJVXpJMU5pSXNJblI1Y0NJNklrcFhWQ0o5LmV5SnBjM01pT2lKemRYQmhZbUZ6WlNJc0luSmxaaUk2SW0xeWRXSmtlbWRqYW05bWFuZHBjbXRrWm5kdklpd2ljbTlzWlNJNkltRnViMjRpTENKcFlYUWlPakUzT1RFNE1qQTROVEVzSW1WNGNDSTZNakV3TnpNNU5qZzFNWDAucy1fVW9KaVJnYi04NF81V2hyUXQwY1NtRkVDVTduczF5Q3ZrMFhHQ0FCUQ==').decode()

payload = {
    "title": "تبليغ هام بخصوص المختبر القادم 🔬",
    "content": "زملائي الطلبة الأعزاء، يرجى مراجعة التجربة الثالثة الخاصة بالمختبر قبل موعد المحاضرة القادمة، مع إحضار دفتر الملاحظات الخاص بالتقارير. بالتوفيق للجميع. [SECTION:ALL]",
    "author_id": "ST-NUST-001630760-413",
    "author_name": "مجتبى عواد",
    "author_role": "ممثل الدفعة",
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

try:
    with urllib.request.urlopen(req) as resp:
        res = json.loads(resp.read().decode('utf-8'))
        print("[SUCCESS] Created announcement ID:", res[0]['id'])
except Exception as e:
    print("[ERROR]:", e)
