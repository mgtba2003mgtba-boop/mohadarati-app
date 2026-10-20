import os

file_path = os.path.join("supabase", "functions", "telegram-webhook", "index.ts")
with open(file_path, "r", encoding="utf-8") as f:
    c = f.read()

# Read new file_id from scripts/new_apk_file_id.txt if it exists
file_id_path = os.path.join("scripts", "new_apk_file_id.txt")
if os.path.exists(file_id_path):
    with open(file_id_path, "r", encoding="utf-8") as f:
        new_id = f.read().strip()
    
    import re
    c = re.sub(r"const APK_FILE_ID = '[^']+';", f"const APK_FILE_ID = '{new_id}';", c)
    print(f"[+] Injected new APK_FILE_ID: {new_id}")

new_android_caption = """  const caption = `🤖 <b>تطبيق محاضراتي للأندرويد (تحديث سحابي دائم)</b>\\n` +
    `━━━━━━━━━━━━━━━━━━━━━\\n` +
    `📦 <b>الإصدار:</b> v1.0.2 (أحدث نسخة هوائية)\\n` +
    `⚡ <b>الميزة:</b> ثبّته مرة واحدة فقط، وسيتحدث التطبيق تلقائياً عند كل تطوير دون الحاجة لإعادة تنزيل الـ APK أبداً!\\n` +
    `━━━━━━━━━━━━━━━━━━━━━\\n` +
    `اضغط على الملف أعلاه لتنزيله ثم اختر <b>تثبيت (Install)</b>.`;"""

# Replace caption in sendAndroidApkFile
import re
c = re.sub(
    r"async function sendAndroidApkFile\(botToken, chatId\) \{[\s\S]*?await sendTelegramDocument",
    f"async function sendAndroidApkFile(botToken, chatId) {{\n{new_android_caption}\n  await sendTelegramDocument",
    c
)

with open(file_path, "w", encoding="utf-8") as f:
    f.write(c)

print("[+] Updated telegram webhook for Dynamic Shell successfully")
