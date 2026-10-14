import os
import sys
import time
import json
import urllib.request
import urllib.error

if hasattr(sys.stdout, 'reconfigure'):
    sys.stdout.reconfigure(encoding='utf-8')

BOT_TOKEN = "8760017532:AAGPiVBa6-TPnSnwuxGWGiR8wTJlKYT8vSM"
ADMIN_CHAT_ID = "7048397159"

SUPABASE_URL = "https://rlupqsmqwvidmwrvqrcc.supabase.co"
SUPABASE_KEY = "sb_publishable_sJM5JiXGzn-jif8EYqXC-g_5_HdADJ4"

INLINE_KEYBOARD = {
    "inline_keyboard": [
        [
            {
                "text": "🌐 فتح المنصة والتسجيل فوراً",
                "url": "https://mohadarati.vercel.app"
            }
        ],
        [
            {
                "text": "📲 تنزيل التطبيق (آيفون / أندرويد)",
                "callback_data": "cmd:app"
            }
        ]
    ]
}

def build_student_message(name, student_id):
    clean_name = name.strip() if name else "عزيزي الطالب"
    clean_id = student_id.strip() if student_id else "ST-NUST"
    return (
        f"🎓 <b>مرحباً بك يا {clean_name}</b>\n\n"
        f"تم إطلاق تطبيق «<b>محاضراتي</b>» رسمياً لقسم هندسة تقنيات الأجهزة الطبية لمتابعة المحاضرات، الجداول الأسبوعية، التبليغات، ونسب الحضور والغياب.\n\n"
        f"🆔 <b>رقمك الجامعي لتسجيل الدخول (انقر عليه للنسخ)</b>:\n"
        f"<code>{clean_id}</code>"
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

def fetch_medical_devices_students():
    """Fetch students belonging to Medical Devices department with telegram_chat_id."""
    url = f"{SUPABASE_URL}/rest/v1/students?select=id,name,department,stage,section,telegram_chat_id&telegram_chat_id=not.is.null"
    headers = {
        "apikey": SUPABASE_KEY,
        "Authorization": f"Bearer {SUPABASE_KEY}"
    }
    req = urllib.request.Request(url, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=20) as resp:
            data = json.loads(resp.read().decode("utf-8"))
            # Filter Medical Devices department
            med_students = []
            seen_chats = set()
            for s in data:
                dept = s.get("department") or ""
                cid = s.get("telegram_chat_id")
                if ("أجهزة" in dept or "اجهزة" in dept) and cid and str(cid).strip():
                    cid_str = str(cid).strip()
                    if cid_str not in seen_chats:
                        seen_chats.add(cid_str)
                        med_students.append(s)
            return med_students
    except Exception as e:
        print(f"[ERROR] Failed to fetch students: {e}")
        return []

def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else "--test"

    if mode == "--test":
        print(f"[INFO] Sending personalized test broadcast to Admin ({ADMIN_CHAT_ID})...")
        test_text = build_student_message("مجتبى عواد حسن", "ST-NUST-001630760-413")
        res = send_telegram_message(ADMIN_CHAT_ID, test_text, INLINE_KEYBOARD)
        if res.get("ok"):
            print("[SUCCESS] Personalized test message delivered to Admin on Telegram!")
        else:
            print(f"[FAILED] Could not send test message: {res}")
        return

    if mode == "--broadcast":
        print("[INFO] Fetching Medical Devices students with Telegram...")
        students = fetch_medical_devices_students()
        total = len(students)
        print(f"[INFO] Found {total} Medical Devices students ready for personalized broadcast.")

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

            if idx % 25 == 0 or idx == total:
                elapsed = time.time() - start_time
                print(f"  Progress: {idx}/{total} sent | Success: {success_count} | Failed: {fail_count} | Elapsed: {elapsed:.1f}s")

            # Rate limit: ~25 msg/sec
            time.sleep(0.04)

        print("=" * 50)
        print(f"[DONE] Medical Devices Broadcast Finished!")
        print(f"  Total Target: {total}")
        print(f"  Success: {success_count}")
        print(f"  Failed: {fail_count}")
        print("=" * 50)

if __name__ == "__main__":
    main()
