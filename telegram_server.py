import os
import re
import sys
import asyncio
from typing import Optional
from contextlib import asynccontextmanager

# ضبط ترميز الطرفية لمنع أخطاء Windows CP1256 مع الإيموجي واللغة العربية
try:
    if sys.stdout.encoding != 'utf-8':
        sys.stdout.reconfigure(encoding='utf-8', errors='replace')
    if sys.stderr.encoding != 'utf-8':
        sys.stderr.reconfigure(encoding='utf-8', errors='replace')
except Exception:
    pass

import time
import shutil
from urllib.parse import quote

from fastapi import FastAPI, Request, Response, HTTPException, status, UploadFile, File, Form
from fastapi.responses import StreamingResponse, JSONResponse
from fastapi.middleware.cors import CORSMiddleware
import uvicorn

from telethon import TelegramClient, events
from telethon.tl.types import MessageMediaDocument, MessageMediaPhoto, DocumentAttributeVideo, DocumentAttributeFilename
from supabase import create_client, Client

# ── 1. إعدادات تيليجرام وسيرفر Supabase ──────────────────────────────────────
API_ID = 2040
API_HASH = "b18441a1ff607e10a989891a5462e627"
BOT_TOKEN = "8816281220:AAFAduddee7N8mD-UNgQIgfQ1yiFaGbdHU8"
ATTENDANCE_BOT_TOKEN = "8760017532:AAGPiVBa6-TPnSnwuxGWGiR8wTJlKYT8vSM"
CHANNEL_ID = -1003875986734

SUPABASE_URL = "https://mrubdzgcjofjwirkdfwo.supabase.co"
SUPABASE_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im1ydWJkemdjam9mandpcmtkZndvIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc5MTgyMDg1MSwiZXhwIjoyMTA3Mzk2ODUxfQ.4sMIDBMCY-qMwk8CFYTpn6_U_JraC5jPXsb8YxSeGZw"

supabase: Client = create_client(SUPABASE_URL, SUPABASE_KEY)
client: Optional[TelegramClient] = None
recently_uploaded_msg_ids: set = set()

# حجم الشريحة الافتراضي لبث الفيديو (1MB إلى 2MB للأداء السلس)
DEFAULT_CHUNK_SIZE = 1024 * 1024  # 1MB


# ── 2. دوال مساعدة لاستخراج بيانات الوسائط ────────────────────────────────────
def extract_media_info(msg):
    if not msg or not msg.media:
        return None
    
    file_size = getattr(msg.file, 'size', 0) if hasattr(msg, 'file') and msg.file else 0
    mime_type = getattr(msg.file, 'mime_type', None) if hasattr(msg, 'file') and msg.file else None
    file_name = getattr(msg.file, 'name', None) if hasattr(msg, 'file') and msg.file else None
    duration = getattr(msg.file, 'duration', 0) if hasattr(msg, 'file') and msg.file else 0

    if not mime_type:
        mime_type = "video/mp4" if isinstance(msg.media, MessageMediaDocument) else "image/jpeg"
    if not file_name:
        ext = ".mp4" if "video" in mime_type else ".jpg" if "image" in mime_type else ".bin"
        file_name = f"lecture_{msg.id}{ext}"

    title = msg.text or file_name
    return {
        "message_id": msg.id,
        "title": title,
        "file_name": file_name,
        "file_size": file_size,
        "mime_type": mime_type,
        "duration": duration or 0,
    }


# ── 3. دورة حياة التطبيق (Lifespan) ──────────────────────────────────────────
@asynccontextmanager
async def lifespan(app: FastAPI):
    global client
    print("🚀 بدء تشغيل عميل تيليجرام MTProto...")
    client = TelegramClient("telegram_bot_session", API_ID, API_HASH)
    await client.start(bot_token=BOT_TOKEN)
    me = await client.get_me()
    print(f"✅ متصل بنجاح كـ بوت: @{me.username} في القناة: {CHANNEL_ID}")

    # معالج تلقائي لمزامنة أي محاضرة جديدة تُرفع في القناة يدوياً من تيليجرام
    @client.on(events.NewMessage(chats=[CHANNEL_ID]))
    async def handle_new_lecture(event):
        msg = event.message
        if not msg or not msg.media:
            return

        # إذا كانت المحاضرة مرفوعة من التطبيق عبر الـ API، تم تسجيلها بالفعل
        if msg.id in recently_uploaded_msg_ids:
            print(f"ℹ️ المحاضرة {msg.id} رُفعت بواسطة التطبيق، تخطي التكرار.")
            recently_uploaded_msg_ids.remove(msg.id)
            return

        # التحقق إن كانت مسجلة مسبقاً في قاعدة البيانات
        try:
            existing = supabase.table("lectures").select("id").eq("telegram_message_id", msg.id).execute()
            if existing.data:
                return
        except Exception:
            pass

        info = extract_media_info(msg)
        if info:
            print(f"📥 وصل ملف جديد في القناة: {info['file_name']} (حجم: {info['file_size']} بايت)")
            try:
                payload = {
                    "title": info["title"] or f"محاضرة رقم {msg.id}",
                    "subject_name": "المقرر العام",
                    "department": "ALL",
                    "stage": "ALL",
                    "telegram_channel_id": CHANNEL_ID,
                    "telegram_message_id": msg.id,
                    "file_name": info["file_name"],
                    "file_size_bytes": info["file_size"],
                    "mime_type": info["mime_type"],
                    "duration_seconds": info["duration"],
                    "uploader_id": "TELEGRAM_AUTO_SYNC",
                    "uploader_name": "قناة المحاضرات",
                    "uploader_role": "admin"
                }
                supabase.table("lectures").insert(payload).execute()
                print(f"✅ تم حفظ المحاضرة {msg.id} في سيرفر Supabase بنجاح!")
            except Exception as ex:
                print(f"[-] خطأ في إدخال المحاضرة بقاعدة البيانات: {ex}")

    yield

    print("🛑 إيقاف عميل تيليجرام...")
    if client:
        await client.disconnect()


app = FastAPI(
    title="NUST Telegram Video Streaming & CDN Server",
    description="سيرفر وسيط لبث وتحميل محاضرات الفيديو الكبيرة من تيليجرام مباشرة",
    version="1.0.0",
    lifespan=lifespan
)

# تفعيل الـ CORS لتطبيق الموبايل والمتصفح
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


# ── 4. مسار الفحص العام (Health Check) ───────────────────────────────────────
@app.get("/")
async def root():
    return {
        "status": "online",
        "service": "NUST Telegram Video Streaming CDN",
        "channel_id": CHANNEL_ID,
        "protocol": "MTProto Direct Streamer (Up to 2GB Support)"
    }


# ── مسار إرسال كود التحقق OTP عبر تيليجرام ──────────────────────────────────
@app.post("/api/telegram/send_otp")
async def send_otp_endpoint(request: Request):
    try:
        data = await request.json()
        chat_id = str(data.get("chat_id", "")).strip()
        student_name = data.get("student_name", "الطالب")
        otp_code = str(data.get("otp_code", "")).strip()
        student_id = str(data.get("student_id", "")).strip()

        if not chat_id or not otp_code:
            return JSONResponse(status_code=400, content={"ok": False, "error": "Missing chat_id or otp_code"})

        # رسالة مختصرة ومباشرة بدون حشو
        text = f"🔐 *كود الاستعادة:* `{otp_code}`\nصالح لمدة 10 دقائق."

        # 1. إرسال الكود مباشرة ودقيقاً عبر بوت نظام البصمة (Attendance Bot)
        sent = False
        import requests
        try:
            resp = requests.post(
                f"https://api.telegram.org/bot{ATTENDANCE_BOT_TOKEN}/sendMessage",
                json={"chat_id": chat_id, "text": text, "parse_mode": "Markdown"},
                timeout=6,
            )
            if resp.status_code == 200:
                sent = True
            else:
                print(f"Attendance Bot API failed: {resp.status_code} - {resp.text}")
        except Exception as e:
            print(f"HTTP request error: {e}")

        # 2. خط الدفاع الاحتياطي عبر عميل السيرفر Telethon في حال الحاجة
        if not sent and client:
            try:
                target = int(chat_id) if chat_id.lstrip('-').isdigit() else chat_id
                await client.send_message(target, text, parse_mode='md')
                sent = True
            except Exception as ex:
                print(f"Telethon send_message error: {ex}")

        if sent:
            return {"ok": True, "message": "OTP sent successfully"}
        else:
            return JSONResponse(status_code=400, content={"ok": False, "error": "تعذر الوصول للمحادثة في تيليجرام"})
    except Exception as e:
        return JSONResponse(status_code=500, content={"ok": False, "error": str(e)})


# ── 5. مسار معلومات المحاضرة (Metadata) ──────────────────────────────────────
@app.get("/api/lecture/{message_id}/info")
async def get_lecture_info(message_id: int):
    if not client:
        raise HTTPException(status_code=503, detail="Telegram client not ready")

    try:
        msg = await client.get_messages(CHANNEL_ID, ids=message_id)
        if not msg or not msg.media:
            raise HTTPException(status_code=404, detail="Lecture file not found in Telegram channel")

        info = extract_media_info(msg)
        return {"ok": True, "lecture": info}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


# ── 6. مسار تدفق الفيديو مع دعم الـ Range Requests (Video Streaming & Seeking) ──
@app.get("/api/lecture/{message_id}/stream")
async def stream_lecture(message_id: int, request: Request):
    """
    بث الفيديو مباشرة مع دعم HTTP 206 Partial Content (التقديم والتأخير السلس)
    يتجاوز حد الـ 20MB ويعمل حتى 2,000MB بدون تحميل مسبق على السيرفر
    """
    if not client:
        raise HTTPException(status_code=503, detail="Telegram client not ready")

    try:
        msg = await client.get_messages(CHANNEL_ID, ids=message_id)
        if not msg or not msg.media:
            raise HTTPException(status_code=404, detail="File not found")

        info = extract_media_info(msg)
        total_size = info["file_size"]
        mime_type = info["mime_type"]

        # قراءة ترويسة الـ Range من مشغل الفيديو
        range_header = request.headers.get("range")

        if range_header:
            # مثال: bytes=1048576-2097151 أو bytes=1048576-
            range_match = re.match(r"bytes=(\d+)-(\d*)", range_header)
            if not range_match:
                raise HTTPException(status_code=416, detail="Invalid Range Header")

            start_byte = int(range_match.group(1))
            end_byte = int(range_match.group(2)) if range_match.group(2) else min(start_byte + DEFAULT_CHUNK_SIZE * 2 - 1, total_size - 1)
            end_byte = min(end_byte, total_size - 1)
            chunk_length = (end_byte - start_byte) + 1

            async def range_stream_generator():
                bytes_sent = 0
                async for chunk in client.iter_download(
                    msg.media,
                    offset=start_byte,
                    request_size=256 * 1024
                ):
                    needed = chunk_length - bytes_sent
                    if len(chunk) > needed:
                        yield chunk[:needed]
                        bytes_sent += needed
                        break
                    else:
                        yield chunk
                        bytes_sent += len(chunk)
                        if bytes_sent >= chunk_length:
                            break

            headers = {
                "Content-Range": f"bytes {start_byte}-{end_byte}/{total_size}",
                "Accept-Ranges": "bytes",
                "Content-Length": str(chunk_length),
                "Content-Type": mime_type,
                "Cache-Control": "public, max-age=3600",
            }
            return StreamingResponse(range_stream_generator(), status_code=status.HTTP_206_PARTIAL_CONTENT, headers=headers)

        else:
            # إذا لم يُطلب Range، بث الملف كاملاً
            async def full_stream_generator():
                async for chunk in client.iter_download(msg.media, request_size=512 * 1024):
                    yield chunk

            headers = {
                "Accept-Ranges": "bytes",
                "Content-Length": str(total_size),
                "Content-Type": mime_type,
            }
            return StreamingResponse(full_stream_generator(), status_code=200, headers=headers)

    except HTTPException:
        raise
    except Exception as e:
        print(f"[-] Streaming error: {e}")
        raise HTTPException(status_code=500, detail=str(e))


# ── 7. مسار التحميل المباشر للمحاضرة (Download with Progress Support) ────────
@app.get("/api/lecture/{message_id}/download")
async def download_lecture(message_id: int):
    """
    تحميل الملف كاملاً بصيغة Attachment مع دعم الـ Resumable Download
    """
    if not client:
        raise HTTPException(status_code=503, detail="Telegram client not ready")

    try:
        msg = await client.get_messages(CHANNEL_ID, ids=message_id)
        if not msg or not msg.media:
            raise HTTPException(status_code=404, detail="File not found")

        info = extract_media_info(msg)
        total_size = info["file_size"]
        file_name = info["file_name"]
        mime_type = info["mime_type"]

        async def download_generator():
            async for chunk in client.iter_download(msg.media, request_size=1024 * 1024):
                yield chunk

        safe_filename = quote(file_name)
        headers = {
            "Content-Disposition": f"attachment; filename=\"{safe_filename}\"; filename*=UTF-8''{safe_filename}",
            "Accept-Ranges": "bytes",
            "Content-Length": str(total_size),
            "Content-Type": mime_type,
        }
        return StreamingResponse(download_generator(), status_code=200, headers=headers)

    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


# ── 8. مسار مزامنة جميع محاضرات القناة تلقائياً مع Supabase ────────────────────
@app.post("/api/sync-channel")
async def sync_all_lectures(latest_id: int = 50):
    """
    مسح القناة واستيراد جميع الفيديوهات والملفات الموجودة بها تلقائياً إلى جدول lectures
    """
    if not client:
        raise HTTPException(status_code=503, detail="Telegram client not ready")

    count = 0
    try:
        id_list = list(range(1, latest_id + 1))
        msgs = await client.get_messages(CHANNEL_ID, ids=id_list)
        for msg in msgs:
            if not msg or not msg.media:
                continue

            info = extract_media_info(msg)
            if not info:
                continue

            # التحقق إن كان السجل موجوداً مسبقاً
            existing = supabase.table("lectures") \
                .select("id") \
                .eq("telegram_message_id", msg.id) \
                .execute()

            if not existing.data:
                payload = {
                    "title": info["title"] or f"محاضرة رقم {msg.id}",
                    "subject_name": "المقرر العام",
                    "department": "ALL",
                    "stage": "ALL",
                    "telegram_channel_id": CHANNEL_ID,
                    "telegram_message_id": msg.id,
                    "file_name": info["file_name"],
                    "file_size_bytes": info["file_size"],
                    "mime_type": info["mime_type"],
                    "duration_seconds": info["duration"],
                    "uploader_id": "TELEGRAM_AUTO_SYNC",
                    "uploader_name": "قناة المحاضرات",
                    "uploader_role": "admin"
                }
                supabase.table("lectures").insert(payload).execute()
                count += 1

        return {"ok": True, "synced_lectures": count, "message": f"تمت مزامنة {count} محاضرات بنجاح!"}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


# ── 9. مسار رفع المحاضرة مباشرة من التطبيق إلى سحابة تيليجرام ────────────────
@app.post("/api/upload-lecture")
async def upload_lecture(
    file: UploadFile = File(...),
    title: str = Form(...),
    subject_name: str = Form(...),
    department: str = Form("ALL"),
    stage: str = Form("ALL"),
    semester: int = Form(1),
    lecture_type: str = Form("theory"),
    professor_name: Optional[str] = Form(None),
    description: Optional[str] = Form(None),
    uploader_id: str = Form("NUST_USER"),
    uploader_name: str = Form("ممثل الشعبة"),
    uploader_role: str = Form("representative"),
):
    """
    رفع ملف محاضرة (فيديو، PDF، مستند) مباشرة من التطبيق إلى قناة تيليجرام
    وحفظ بياناته في قاعدة بيانات Supabase دون الحاجة لفتح تيليجرام إطلاقاً
    """
    if not client:
        raise HTTPException(status_code=503, detail="Telegram client not ready")

    temp_dir = os.path.join(os.path.dirname(os.path.abspath(__file__)), "temp_uploads")
    os.makedirs(temp_dir, exist_ok=True)

    original_name = file.filename or "lecture_file.bin"
    ext = os.path.splitext(original_name)[1]
    timestamp = int(time.time())
    temp_file_path = os.path.join(temp_dir, f"up_{timestamp}_{original_name}")

    try:
        # 1. حفظ الملف محلياً بشكل مؤقت بتدفق متسلسل
        with open(temp_file_path, "wb") as buffer:
            shutil.copyfileobj(file.file, buffer)

        file_size = os.path.getsize(temp_file_path)
        print(f"📦 تم استقبال الملف: {original_name} بحجم {file_size} بايت. جاري الرفع إلى تيليجرام...")

        # 2. إنشاء الوصف
        caption_lines = [
            f"📚 {title}",
            f"📖 المقرر: {subject_name}",
            f"🏛 القسم: {department} | المرحلة: {stage}",
        ]
        if professor_name and professor_name.strip():
            caption_lines.append(f"👨‍🏫 الأستاذ: {professor_name.strip()}")
        if description and description.strip():
            caption_lines.append(f"📝 ملاحظات: {description.strip()}")
        caption_lines.append(f"👤 نُشر بواسطة: {uploader_name} ({uploader_role})")
        caption = "\n".join(caption_lines)

        # 3. الرفع عبر عميل تيليجرام MTProto
        is_video = "video" in (file.content_type or "") or ext.lower() in [".mp4", ".mkv", ".mov", ".avi"]
        sent_msg = await client.send_file(
            CHANNEL_ID,
            temp_file_path,
            caption=caption,
            file_name=original_name,
            supports_streaming=is_video,
        )

        recently_uploaded_msg_ids.add(sent_msg.id)
        print(f"✅ تم رفع الملف إلى تيليجرام بنجاح! Message ID: {sent_msg.id}")

        # 4. استخراج الخصائص
        info = extract_media_info(sent_msg) or {}
        real_mime = file.content_type or info.get("mime_type") or "application/octet-stream"

        # 5. حفظ السجل في Supabase
        payload = {
            "title": title,
            "subject_name": subject_name,
            "department": department,
            "stage": stage,
            "semester": semester,
            "type": lecture_type,
            "professor_name": professor_name or None,
            "description": description or None,
            "telegram_channel_id": CHANNEL_ID,
            "telegram_message_id": sent_msg.id,
            "file_name": original_name,
            "file_size_bytes": file_size,
            "mime_type": real_mime,
            "duration_seconds": info.get("duration", 0),
            "uploader_id": uploader_id,
            "uploader_name": uploader_name,
            "uploader_role": uploader_role,
        }

        db_res = supabase.table("lectures").insert(payload).execute()
        created_row = db_res.data[0] if db_res.data else {}

        return {
            "ok": True,
            "message": "تم نشر المحاضرة ورفعها إلى السحابة بنجاح!",
            "lecture": created_row,
            "telegram_message_id": sent_msg.id,
        }

    except Exception as e:
        print(f"[-] خطأ أثناء رفع المحاضرة: {e}")
        raise HTTPException(status_code=500, detail=str(e))
    finally:
        # 6. تنظيف الملف المؤقت
        if os.path.exists(temp_file_path):
            try:
                os.remove(temp_file_path)
            except Exception:
                pass


# ── 10. مسار رفع أي ملف أو صورة إلى سحابة تيليجرام (للجداول والبوسترات) ───────
@app.post("/api/upload-file")
async def upload_general_file(
    file: UploadFile = File(...),
    caption: Optional[str] = Form(None),
    file_type: str = Form("general"),
):
    """
    رفع أي ملف أو صورة (جدول، بوستر، PDF) مباشرة إلى قناة تيليجرام
    وإرجاع رابط الـ CDN الخاص بها
    """
    if not client:
        raise HTTPException(status_code=503, detail="Telegram client not ready")

    temp_dir = os.path.join(os.path.dirname(os.path.abspath(__file__)), "temp_uploads")
    os.makedirs(temp_dir, exist_ok=True)

    original_name = file.filename or "file.bin"
    ext = os.path.splitext(original_name)[1]
    timestamp = int(time.time())
    temp_file_path = os.path.join(temp_dir, f"gen_{timestamp}_{original_name}")

    try:
        with open(temp_file_path, "wb") as buffer:
            shutil.copyfileobj(file.file, buffer)

        file_size = os.path.getsize(temp_file_path)
        print(f"📦 تم استقبال ملف {file_type}: {original_name} بحجم {file_size} بايت. جاري الرفع إلى تيليجرام...")

        tag = "📅 جدول دراسي/امتحاني" if file_type == "schedule" else "📢 إعلان وبوستر رسمي" if file_type == "banner" else "📁 ملف جامعي"
        final_caption = f"{tag}\n{caption}" if caption else tag

        sent_msg = await client.send_file(
            CHANNEL_ID,
            temp_file_path,
            caption=final_caption,
            file_name=original_name,
        )

        recently_uploaded_msg_ids.add(sent_msg.id)
        print(f"✅ تم رفع الملف إلى تيليجرام بنجاح! Message ID: {sent_msg.id}")

        info = extract_media_info(sent_msg) or {}
        real_mime = file.content_type or info.get("mime_type") or "application/octet-stream"

        return {
            "ok": True,
            "message": "تم رفع الملف إلى سحابة تيليجرام بنجاح",
            "telegram_message_id": sent_msg.id,
            "file_name": original_name,
            "file_size": file_size,
            "mime_type": real_mime,
            "file_url": f"/api/file/{sent_msg.id}",
        }

    except Exception as e:
        print(f"[-] خطأ أثناء رفع الملف: {e}")
        raise HTTPException(status_code=500, detail=str(e))
    finally:
        if os.path.exists(temp_file_path):
            try:
                os.remove(temp_file_path)
            except Exception:
                pass


# ── 11. مسار عرض الصور والملفات المباشر (Direct CDN File/Image View) ─────────
@app.get("/api/file/{message_id}")
async def view_file(message_id: int):
    """
    عرض ملف أو صورة مباشرة من تيليجرام مع ترويسة Content-Type الصحيحة
    """
    if not client:
        raise HTTPException(status_code=503, detail="Telegram client not ready")

    try:
        msg = await client.get_messages(CHANNEL_ID, ids=message_id)
        if not msg or not msg.media:
            raise HTTPException(status_code=404, detail="File not found")

        info = extract_media_info(msg) or {}
        total_size = info.get("file_size", 0)
        mime_type = info.get("mime_type") or "application/octet-stream"
        file_name = info.get("file_name") or f"file_{message_id}"

        # للأحجام حتى 25MB (مثل الصور والمستندات)، نرسل الملف بالكامل مباشرة
        # هذا يمنع انقطاع التدفق في Flutter Web ومتصفحات الهواتف
        if total_size <= 25 * 1024 * 1024:
            file_bytes = await client.download_media(msg.media, bytes)
            return Response(
                content=file_bytes,
                status_code=200,
                media_type=mime_type,
                headers={
                    "Content-Disposition": f"inline; filename=\"{quote(file_name)}\"; filename*=UTF-8''{quote(file_name)}",
                    "Content-Length": str(len(file_bytes)),
                    "Cache-Control": "public, max-age=86400",
                    "Access-Control-Allow-Origin": "*",
                    "Access-Control-Allow-Methods": "GET, HEAD, OPTIONS",
                    "Access-Control-Allow-Headers": "*",
                }
            )

        async def file_generator():
            async for chunk in client.iter_download(msg.media, request_size=512 * 1024):
                yield chunk

        headers = {
            "Content-Type": mime_type,
            "Content-Length": str(total_size),
            "Cache-Control": "public, max-age=86400",
            "Accept-Ranges": "bytes",
            "Access-Control-Allow-Origin": "*",
            "Access-Control-Allow-Methods": "GET, HEAD, OPTIONS",
            "Access-Control-Allow-Headers": "*",
        }
        return StreamingResponse(file_generator(), status_code=200, headers=headers)

    except HTTPException:
        raise
    except Exception as e:
        print(f"[-] Error in view_file: {e}")
        raise HTTPException(status_code=500, detail=str(e))


if __name__ == "__main__":
    # تشغيل السيرفر على البورت 8050 لجميع الأجهزة والشبكة
    uvicorn.run(app, host="0.0.0.0", port=8050)

