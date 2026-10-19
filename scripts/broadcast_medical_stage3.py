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
                "text": "🌐 فتح منصة محاضراتي والتسجيل فوراً",
                "url": "https://mohadarati.vercel.app"
            }
        ],
        [
            {
                "text": "📲 تنزيل التحديث للأندرويد (APK)",
                "callback_data": "cmd:app"
            }
        ]
    ]
}

def build_student_message(name, student_id):
    clean_name = name.strip() if name else "عزيزي الطالب"
    clean_id = student_id.strip() if student_id else "ST-NUST"
    return (
        f"📢 <b>تنويه وتوجيه أكاديمي هام جداً | المرحلة الثالثة</b>\n"
        f"🏛️ <b>قسم هندسة تقنيات الأجهزة الطبية</b>\n"
        f"━━━━━━━━━━━━━━━━━━━━━\n"
        f"مرحباً بك يا <b>{clean_name}</b> 🎓\n\n"
        f"يرجى من جميع طلبة المرحلة الثالثة الانتباه للتعليمات الأكاديمية الجديدة لضمان استلام كافة المواد والمحاضرات:\n\n"
        f"1️⃣ <b>اعتماد المنصة رسمياً:</b>\n"
        f"ابتداءً من اليوم، ستُنشر جميع <b>المحاضرات، الملازم، والجداول، والتبليغات</b> حصراً عبر منصة «<b>محاضراتي</b>». إذا لم تسجل حسابك حتى الآن، يرجى الدخول فوراً وتفعيل قيدك برقمك الجامعي.\n\n"
        f"2️⃣ <b>إجراء ضروري: حذف النسخ القديمة:</b>\n"
        f"لضمان عمل المنظومة بأحدث الميزات ودون أي مشاكل:\n"
        f"• 🍏 <b>مستخدمو الآيفون (iOS):</b> يرجى <b>حذف ملف التعريف القديم</b> بالذهاب إلى:\n"
        f"  <i>(الإعدادات ⚙️ ➔ عام ➔ VPN وإدارة الأجهزة ➔ حذف ملف التعريف)</i>.\n"
        f"• 🤖 <b>مستخدمو الأندرويد (Android):</b> يرجى <b>إلغاء تثبيت النسخة القديمة</b> وتنزيل النسخة المحدثة عبر إرسال <code>/app</code> في البوت.\n\n"
        f"3️⃣ <b>الخيار الأفضل والمثالي للجميع 🌟:</b>\n"
        f"نوصي بشدة بفتح رابط المنصة عبر <b>المتصفح (Safari للآيفون أو Chrome للأندرويد)</b> وعمل:\n"
        f"📲 <b>(إضافة إلى الشاشة الرئيسية / Add to Home Screen)</b>\n"
        f"ليعمل معك التطبيق مباشرة، بسرعة فائقة، ومع ميزة التحديث التلقائي الفوري دون الحاجة لتنزيل أي ملفات يدوياً مستقبلاً!\n"
        f"━━━━━━━━━━━━━━━━━━━━━\n"
        f"🆔 <b>رقمك الجامعي لتسجيل الدخول (انقر للنسخ):</b>\n"
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

def fetch_stage3_students():
    url = f"{SUPABASE_URL}/rest/v1/students?select=id,name,department,stage,section,telegram_chat_id&telegram_chat_id=not.is.null"
    headers = {
        "apikey": SUPABASE_KEY,
        "Authorization": f"Bearer {SUPABASE_KEY}"
    }
    req = urllib.request.Request(url, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=20) as resp:
            data = json.loads(resp.read().decode("utf-8"))
            stage3_students = []
            seen_chats = set()
            for s in data:
                dept = s.get("department") or ""
                stage = s.get("stage") or ""
                cid = s.get("telegram_chat_id")
                is_med = ("أجهزة" in dept or "اجهزة" in dept)
                is_stg3 = ("3" in stage or "ثالث" in stage)
                if is_med and is_stg3 and cid and str(cid).strip():
                    cid_str = str(cid).strip()
                    if cid_str not in seen_chats:
                        seen_chats.add(cid_str)
                        stage3_students.append(s)
            return stage3_students
    except Exception as e:
        print(f"[ERROR] Failed to fetch students: {e}")
        return []

def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else "--test"

    if mode == "--test":
        print(f"[INFO] Sending test notification to Admin ({ADMIN_CHAT_ID})...")
        test_text = build_student_message("مجتبى عواد حسن (معاينة تجريبية)", "ST-NUST-001630760-413")
        res = send_telegram_message(ADMIN_CHAT_ID, test_text, INLINE_KEYBOARD)
        if res.get("ok"):
            print("[SUCCESS] Test notification sent to Admin successfully on Telegram!")
        else:
            print(f"[FAILED] Could not send test notification: {res}")
        return

    if mode == "--broadcast":
        print("[INFO] Fetching Medical Devices Stage 3 students...")
        students = fetch_stage3_students()
        total = len(students)
        print(f"[INFO] Found {total} students in Stage 3 ready for broadcast.")

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

            if idx % 10 == 0 or idx == total:
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
