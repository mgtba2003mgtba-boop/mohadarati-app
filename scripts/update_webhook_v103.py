import os
import re

file_path = os.path.join("supabase", "functions", "telegram-webhook", "index.ts")
with open(file_path, "r", encoding="utf-8") as f:
    c = f.read()

new_id = "BQACAgIAAxkDAAJUlWrWtS7DRyh2-0uM6QFXR_C05k-TAALLrgACgMywSjulL4dGhL7gPQQ"
c = re.sub(r"const APK_FILE_ID = '[^']+';", f"const APK_FILE_ID = '{new_id}';", c)

new_android_caption = """  const caption = `🤖 <b>تطبيق محاضراتي للأندرويد (APK)</b>\\n` +
    `━━━━━━━━━━━━━━━━━━━━━\\n` +
    `📦 <b>الإصدار المستقر:</b> v1.0.3 (النسخة الأصلية السريعة)\\n` +
    `⚡ <b>التحسينات:</b> أداء فائق 60fps، واستجابة ونشر فوري مع استقرار كامل\\n` +
    `━━━━━━━━━━━━━━━━━━━━━\\n` +
    `اضغط على الملف أعلاه لتنزيله ثم اختر <b>تثبيت (Install)</b>.`;"""

c = re.sub(
    r"async function sendAndroidApkFile\(botToken, chatId\) \{[\s\S]*?await sendTelegramDocument",
    f"async function sendAndroidApkFile(botToken, chatId) {{\n{new_android_caption}\n  await sendTelegramDocument",
    c
)

c = re.sub(r"v1\.0\.\d", "v1.0.3", c)

with open(file_path, "w", encoding="utf-8") as f:
    f.write(c)

print("[+] Updated telegram webhook to v1.0.3 successfully")
