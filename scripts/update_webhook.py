import os

file_path = os.path.join("supabase", "functions", "telegram-webhook", "index.ts")
with open(file_path, "r", encoding="utf-8") as f:
    c = f.read()

old_id = "BQACAgIAAxkDAAJUfmrWq3PDErGBonQ017bCmeILlRRxAAK8rgACgMywSp9XZYWwc9zcPQQ"
new_id = "BQACAgIAAxkDAAJUkGrWr_WW50DUKL86DjSYCHMTvLRPAALErgACgMywSoJ4sLkvJ2z_PQQ"
if old_id in c:
    c = c.replace(old_id, new_id)
    print("[+] Replaced APK_FILE_ID")
else:
    print("[!] old_id not found")

# Replace Android caption
old_android_pattern = "📦 <b>الإصدار الجديد:</b> v1.0.1"
new_android_pattern = "📦 <b>الإصدار الجديد:</b> v1.0.2 (أحدث إصدار)\n    ⚡ <b>التحسينات:</b> تسريع جذري وسلاسة النشر الفوري"
if old_android_pattern in c:
    # First occurrence is Android
    c = c.replace(old_android_pattern, new_android_pattern, 1)
    print("[+] Updated Android caption")

# Replace iOS caption
old_ios_pattern = "📦 <b>الإصدار الجديد:</b> v1.0.1 (أحدث نسخة)"
new_ios_pattern = "📦 <b>الإصدار الجديد:</b> v1.0.2 (أحدث نسخة)\n    ⚡ <b>التحسينات:</b> تسريع جذري واستجابة فورية"
if old_ios_pattern in c:
    c = c.replace(old_ios_pattern, new_ios_pattern, 1)
    print("[+] Updated iOS caption")

with open(file_path, "w", encoding="utf-8") as f:
    f.write(c)

print("[+] Done updating webhook index.ts")
