import os
import sys
import time
import json
import urllib.request
import urllib.error
import base64

if hasattr(sys.stdout, 'reconfigure'):
    sys.stdout.reconfigure(encoding='utf-8')

BOT_TOKEN = os.environ.get("TELEGRAM_BOT_TOKEN") or base64.b64decode(b"ODc2MDAxNzUzMjpBQUhjb2NvYkQxLU1jTVpYcV9Yc2VMUmZqRHNQUWhZbUsxQQ==").decode('utf-8')
ADMIN_CHAT_ID = "7048397159"

SUPABASE_URL = "https://rlupqsmqwvidmwrvqrcc.supabase.co"
SUPABASE_KEY = "sb_publishable_sJM5JiXGzn-jif8EYqXC-g_5_HdADJ4"

INLINE_KEYBOARD = {
    "inline_keyboard": [
        [
            {
                "text": "🌟 الخيار الأفضل: المتصفح واختصار الشاشة",
                "url": "https://mohadarati.vercel.app"
            }
        ],
        [
            {
                "text": "🍏 تحديث الآيفون (iOS)",
                "callback_data": "cmd:ios"
            },
            {
                "text": "🤖 تحديث الأندرويد (APK)",
                "callback_data": "cmd:apk"
            }
        ]
    ]
}

def build_student_message(name, student_id=None):
    clean_name = name.strip() if name else "عزيزي الطالب"
    return (
        f"🎓 <b>مرحباً {clean_name}</b>\n"
        f"━━━━━━━━━━━━━━━━━━━━━\n"
        f"من الآن المحاضرات والتبليغات تنزل على منصة «<b>محاضراتي</b>»، إذا بعدك ما مسجل ادخل وسجل حسابك الآن.\n\n"
        f"إذا منزل التطبيق بجهازك، ضروري تحدثه لآخر إصدار لتصلك كافة المحاضرات والميزات الجديدة، عبر إرسال <code>/app</code> بالبوت.\n\n"
        f"🌟 <b>الخيار الأفضل: المتصفح واختصار الشاشة</b>\n"
        f"افتح الرابط وسوي إضافة للشاشة، يضمن وصول كل التحديثات تلقائياً لحين اكتمال النشر على <b>Google Play</b> و <b>App Store</b>."
    )

def send_telegram_message(chat_id, text, reply_markup):
    url = f"https://api.telegram.org/bot{BOT_TOKEN}/sendMessage"
    payload = {
        "chat_id": chat_id,
        "text": text,
        "parse_mode": "HTML",
        "reply_markup": reply_markup
    }
    data = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(
        url,
        data=data,
        headers={"Content-Type": "application/json"}
    )
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            return json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        err_body = e.read().decode("utf-8")
        return {"ok": False, "error": err_body}
    except Exception as e:
        return {"ok": False, "error": str(e)}

def fetch_stage4_students():
    url = f"{SUPABASE_URL}/rest/v1/students?select=id,name,department,stage,section,telegram_chat_id&telegram_chat_id=not.is.null"
    headers = {
        "apikey": SUPABASE_KEY,
        "Authorization": f"Bearer {SUPABASE_KEY}"
    }
    req = urllib.request.Request(url, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=20) as resp:
            data = json.loads(resp.read().decode("utf-8"))
            stage4_students = []
            seen_chats = set()
            for s in data:
                dept = s.get("department") or ""
                stage = s.get("stage") or ""
                cid = s.get("telegram_chat_id")
                is_med = ("أجهزة" in dept or "اجهزة" in dept)
                is_stg4 = ("4" in stage or "رابع" in stage)
                if is_med and is_stg4 and cid and str(cid).strip():
                    cid_str = str(cid).strip()
                    if cid_str not in seen_chats:
                        seen_chats.add(cid_str)
                        stage4_students.append(s)
            return stage4_students
    except Exception as e:
        print(f"[ERROR] Failed to fetch students: {e}")
        return []

def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else "--test"

    if mode == "--test":
        print(f"[INFO] Sending test notification for Stage 4 to Admin ({ADMIN_CHAT_ID})...")
        test_text = build_student_message("مجتبى عواد حسن (معاينة المرحلة الرابعة)", "ST-NUST-001630760-413")
        res = send_telegram_message(ADMIN_CHAT_ID, test_text, INLINE_KEYBOARD)
        if res.get("ok"):
            print("[SUCCESS] Test notification sent to Admin successfully on Telegram!")
        else:
            print(f"[FAILED] Could not send test notification: {res}")
        return

    if mode == "--broadcast":
        print("[INFO] Fetching Medical Devices Stage 4 students...")
        students = fetch_stage4_students()
        total = len(students)
        print(f"[INFO] Found {total} students in Stage 4 ready for broadcast.")

        success_count = 0
        fail_count = 0
        start_time = time.time()

        for idx, s in enumerate(students, 1):
            cid = str(s.get("telegram_chat_id")).strip()
            name = s.get("name") or "عزيزي الطالب"
            sid = s.get("id") or "ST-NUST"
            text = build_student_message(name, sid)

            res = send_telegram_message(cid, text, INLINE_KEYBOARD)
            if res.get("ok"):
                success_count += 1
            else:
                fail_count += 1

            if idx % 20 == 0 or idx == total:
                elapsed = time.time() - start_time
                print(f"  Progress: {idx}/{total} sent | Success: {success_count} | Failed: {fail_count} | Elapsed: {elapsed:.1f}s")

            time.sleep(0.04)

        print("=" * 50)
        print(f"[DONE] Broadcast Finished!")
        print(f"  Total: {total}")
        print(f"  Success: {success_count}")
        print(f"  Failed: {fail_count}")
        print("=" * 50)

if __name__ == "__main__":
    main()
