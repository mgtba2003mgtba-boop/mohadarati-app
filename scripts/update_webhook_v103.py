import os
import re

file_path = os.path.join("supabase", "functions", "telegram-webhook", "index.ts")
with open(file_path, "r", encoding="utf-8") as f:
    c = f.read()

new_id = "BQACAgIAAxkDAAJVamrXUFxGtDmxVHFfl3JYNWITqCO9AAKOowACgMy4Sh6KBZKtoBAhPQQ"
c = re.sub(r"const APK_FILE_ID = '[^']+';", f"const APK_FILE_ID = '{new_id}';", c)
c = re.sub(r"v1\.0\.\d", "v1.0.4", c)

with open(file_path, "w", encoding="utf-8") as f:
    f.write(c)

print("[+] Updated telegram-webhook index.ts with new APK_FILE_ID v1.0.4")
