import os
import sys
import json
import base64
import urllib.request
import urllib.error
import time

if hasattr(sys.stdout, 'reconfigure'):
    sys.stdout.reconfigure(encoding='utf-8')

# 1. إعدادات Telegram Bot
BOT_TOKEN = '8816281220:AAFAduddee7N8mD-UNgQIgfQ1yiFaGbdHU8'
CHANNEL_ID = -1003875986734

# 2. إعدادات Supabase
SUPABASE_KEY = base64.b64decode('ZXlKaGJHY2lPaUpJVXpJMU5pSXNJblI1Y0NJNklrcFhWQ0o5LmV5SnBjM01pT2lKemRYQmhZbUZ6WlNJc0luSmxaaUk2SW0xeWRXSmtlbWRqYW05bWFuZHBjbXRrWm5kdklpd2ljbTlzWlNJNkltRnViMjRpTENKcFlYUWlPakUzT1RFNE1qQTROVEVzSW1WNGNDSTZNakV3TnpNNU5qZzFNWDAucy1fVW9KaVJnYi04NF81V2hyUXQwY1NtRkVDVTduczF5Q3ZrMFhHQ0FCUQ==').decode()
SUPABASE_URL = 'https://mrubdzgcjofjwirkdfwo.supabase.co/rest/v1/lectures'

FOLDER_PATH = r'C:\Users\Almustaqbal\Downloads\محاضرات_الاجهزة_الطبية_المرحلة_الرابعة'

# خريطة أسماء المحاضرات المنظمة
LECTURE_TITLES = {
    "01": "المحاضرة 01: غرفة العمليات والأجهزة الجراحية (Operating Room Equipments)",
    "02": "المحاضرة 02: جهاز الشفط الجراحي (Surgical Suction Unit)",
    "03": "المحاضرة 03: جهاز الصدمات القلبية (Cardiac Defibrillators)",
    "04": "المحاضرة 04: وحدة كرسي طب الأسنان (Dental Unit System)",
    "05": "المحاضرة 05: أجهزة مراقبة نبض الجنين والسونار (FHR and Labor Monitoring)",
    "06": "المحاضرة 06: جهاز التخدير (Anesthesia Machine)",
    "07": "المحاضرة 07: جهاز الجراحة الكهربائية والكي (Electrosurgical Unit Diathermy)",
    "08": "المحاضرة 08: الليزر في جراحة العيون (Laser in Ophthalmic Surgery)",
    "09": "المحاضرة 09: جهاز غسيل الكلى الاصطناعية (Hemodialysis Machine)",
    "10": "المحاضرة 10: جهاز القلب والرئة الاصطناعي (Heart Lung Machine)",
    "11": "المحاضرة 11: أجهزة مراقبة المريض والعناية المركزة (Intensive Care Units)",
    "12": "المحاضرة 12: منظم ضربات القلب (Cardiac Pacemakers)",
    "13": "المحاضرة 13: جهاز التنفس الاصطناعي (Mechanical Ventilators)",
    "14": "المحاضرة 14: القوقعة الاصطناعية (Cochlear Prosthesis)",
    "15": "المحاضرة 15: كرسي الأنف والأذن والحنجرة (ENT Chair Unit)",
}

def upload_file_to_telegram(file_path, title):
    file_name = os.path.basename(file_path)
    file_size = os.path.getsize(file_path)
    
    caption = (
        f"📚 {title}\n"
        f"📖 المقرر: الأجهزة العلاجية الطبية I\n"
        f"🏛 القسم: هندسة تقنيات الأجهزة الطبية | المرحلة الرابعة\n"
        f"🏷️ الشعب: جميع الشعب (A, B, C, D)\n"
        f"👤 نُشر بواسطة: مجتبى عواد (admin)"
    )

    boundary = f"----WebKitFormBoundary{int(time.time()*1000)}"
    body = []

    def add_field(k, v):
        body.append(f"--{boundary}\r\n".encode("utf-8"))
        body.append(f'Content-Disposition: form-data; name="{k}"\r\n\r\n'.encode("utf-8"))
        body.append(f"{v}\r\n".encode("utf-8"))

    add_field("chat_id", str(CHANNEL_ID))
    add_field("caption", caption)

    body.append(f"--{boundary}\r\n".encode("utf-8"))
    body.append(f'Content-Disposition: form-data; name="document"; filename="{file_name}"\r\n'.encode("utf-8"))
    body.append(b"Content-Type: application/pdf\r\n\r\n")

    with open(file_path, "rb") as f:
        body.append(f.read())
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

    for attempt in range(1, 4):
        try:
            with urllib.request.urlopen(req, timeout=120) as resp:
                res = json.loads(resp.read().decode("utf-8"))
                if res.get("ok"):
                    result = res["result"]
                    msg_id = result.get("message_id")
                    doc = result.get("document", {})
                    file_id = doc.get("file_id")
                    
                    # استخراج المسار المباشر للملف
                    direct_url = resolve_direct_url(file_id)
                    return {
                        "ok": True,
                        "msg_id": msg_id,
                        "file_id": file_id,
                        "direct_url": direct_url,
                        "file_size": file_size,
                        "file_name": file_name,
                    }
        except Exception as e:
            print(f"[-] Telegram attempt {attempt} error for {file_name}: {e}")
            time.sleep(2)

    return {"ok": False, "error": "Telegram upload failed after 3 attempts"}

def resolve_direct_url(file_id):
    if not file_id:
        return None
    try:
        req = urllib.request.Request(f"https://api.telegram.org/bot{BOT_TOKEN}/getFile?file_id={file_id}")
        with urllib.request.urlopen(req, timeout=30) as resp:
            data = json.loads(resp.read().decode("utf-8"))
            file_path = data.get("result", {}).get("file_path")
            if file_path:
                return f"https://api.telegram.org/file/bot{BOT_TOKEN}/{file_path}"
    except Exception as e:
        print(f"[-] Error resolving getFile for {file_id}: {e}")
    return None

def insert_lecture_to_supabase(lecture_data):
    data = json.dumps(lecture_data).encode("utf-8")
    req = urllib.request.Request(
        SUPABASE_URL,
        data=data,
        headers={
            "apikey": SUPABASE_KEY,
            "Authorization": "Bearer " + SUPABASE_KEY,
            "Content-Type": "application/json",
            "Prefer": "return=representation"
        }
    )
    for attempt in range(1, 4):
        try:
            with urllib.request.urlopen(req, timeout=30) as resp:
                res = json.loads(resp.read().decode("utf-8"))
                return res[0]["id"]
        except Exception as e:
            print(f"[-] Supabase insert attempt {attempt} error: {e}")
            time.sleep(2)
    return None

def main():
    if not os.path.exists(FOLDER_PATH):
        print(f"[ERROR] Folder does not exist: {FOLDER_PATH}")
        sys.exit(1)

    files = [f for f in os.listdir(FOLDER_PATH) if f.lower().endswith('.pdf')]
    files.sort()

    print(f"[*] Found {len(files)} lectures in {FOLDER_PATH}")

    success_count = 0
    for idx, fname in enumerate(files, start=1):
        full_path = os.path.join(FOLDER_PATH, fname)
        
        # استخراج رقم المحاضرة (e.g. 01, 02...)
        num_str = f"{idx:02d}"
        for k in LECTURE_TITLES:
            if f"_{k}_" in fname or fname.startswith(f"المحاضرة_{k}"):
                num_str = k
                break
        
        title = LECTURE_TITLES.get(num_str, f"المحاضرة {num_str}: {os.path.splitext(fname)[0]}")
        print(f"\n[+] ({idx}/{len(files)}) Uploading: {title} ...")

        tg_res = upload_file_to_telegram(full_path, title)
        if not tg_res.get("ok"):
            print(f"[!] FAILED Telegram upload for: {fname}")
            continue

        print(f"    [+] Telegram Message ID: {tg_res['msg_id']} | File ID: {tg_res['file_id'][:15]}...")

        lecture_payload = {
            "title": title,
            "subject_name": "الأجهزة العلاجية الطبية I",
            "subject_code": "MIET4101",
            "department": "هندسة تقنيات الأجهزة الطبية",
            "stage": "المرحلة الرابعة",
            "semester": 1,
            "type": "theory",
            "drive_url": tg_res.get("direct_url") or "telegram",
            "description": "محاضرة معتمدة لمقرر الأجهزة العلاجية الطبية I [SECTION:ALL]",
            "uploader_id": "ST-NUST-001630760-413",
            "uploader_name": "مجتبى عواد",
            "uploader_role": "admin",
            "telegram_channel_id": CHANNEL_ID,
            "telegram_message_id": tg_res["msg_id"],
            "telegram_file_id": tg_res["file_id"],
            "file_name": tg_res["file_name"],
            "file_size_bytes": tg_res["file_size"],
            "mime_type": "application/pdf"
        }

        lec_id = insert_lecture_to_supabase(lecture_payload)
        if lec_id:
            print(f"    [SUCCESS] Saved to Supabase DB ID: {lec_id}")
            success_count += 1
        else:
            print(f"    [!] FAILED Supabase DB insert for: {fname}")

        time.sleep(1)

    print(f"\n==========================================")
    print(f"[DONE] Successfully uploaded {success_count}/{len(files)} lectures!")
    print(f"==========================================")

if __name__ == '__main__':
    main()
