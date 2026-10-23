import os
import shutil
import subprocess

PROJECT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
BUILD_WEB = os.path.join(PROJECT_ROOT, "build", "web")
WEB_SRC = os.path.join(PROJECT_ROOT, "web")

# Read token from environment variable if provided
token = os.environ.get("GITHUB_TOKEN") or os.environ.get("VERCEL_DEPLOY_TOKEN")
if not token:
    token_file = os.path.join(os.path.dirname(__file__), ".deploy_token")
    if os.path.exists(token_file):
        with open(token_file, "r") as f:
            token = f.read().strip()

print(f"[*] Preparing Vercel deployment from: {BUILD_WEB}")

# 1. Ensure vercel.json is present
shutil.copy2(os.path.join(WEB_SRC, "vercel.json"), os.path.join(BUILD_WEB, "vercel.json"))
print("[+] Copied vercel.json")

# 2. Ensure api/ folder is present
api_src = os.path.join(WEB_SRC, "api")
api_dst = os.path.join(BUILD_WEB, "api")
if os.path.exists(api_dst):
    shutil.rmtree(api_dst)
shutil.copytree(api_src, api_dst)
print("[+] Copied api/ folder")

# 3. Ensure static web files, mobileconfig, pdf_viewer, sw-notify, and media
for f in ["mohadarati.mobileconfig", "ios_install_guide.gif", "ios_install_guide.mp4", "pdf_viewer.html", "favicon.png", "manifest.json", "sw-notify.js"]:
    src_f = os.path.join(WEB_SRC, f)
    if os.path.exists(src_f):
        shutil.copy2(src_f, os.path.join(BUILD_WEB, f))
        print(f"[+] Copied {f}")

icons_src = os.path.join(WEB_SRC, "icons")
icons_dst = os.path.join(BUILD_WEB, "icons")
if os.path.exists(icons_src):
    if os.path.exists(icons_dst):
        shutil.rmtree(icons_dst)
    shutil.copytree(icons_src, icons_dst)
    print("[+] Copied icons/ folder")

# 3.5. Ensure latest Android APK is copied for In-App Auto Updates
apk_src = os.path.join(PROJECT_ROOT, "build", "app", "outputs", "flutter-apk", "app-arm64-v8a-release.apk")
if os.path.exists(apk_src):
    shutil.copy2(apk_src, os.path.join(BUILD_WEB, "Mohadarati.apk"))
    print(f"[+] Copied latest APK ({os.path.getsize(apk_src)} bytes) to build/web/Mohadarati.apk")

# 4. Generate dynamic version.json and update index.html
import json
import time
import re

build_time = int(time.time())
app_v = "1.0.5"
android_vc = 6

pubspec_path = os.path.join(PROJECT_ROOT, "pubspec.yaml")
if os.path.exists(pubspec_path):
    with open(pubspec_path, "r", encoding="utf-8") as f:
        p_content = f.read()
    m = re.search(r'version:\s*([0-9\.]+)\+([0-9]+)', p_content)
    if m:
        app_v = m.group(1)
        android_vc = int(m.group(2))

# Extract the true compiled versionCode from APK badging if available
aapt_tool = os.path.expandvars(r"%LOCALAPPDATA%\Android\Sdk\build-tools\34.0.0\aapt.exe")
rel_apk = r"build\app\outputs\flutter-apk\app-arm64-v8a-release.apk"
if os.path.exists(rel_apk) and os.path.exists(aapt_tool):
    try:
        aapt_res = subprocess.run([aapt_tool, "dump", "badging", rel_apk], capture_output=True, text=True, errors="ignore")
        vc_match = re.search(r"versionCode='(\d+)'", aapt_res.stdout)
        if vc_match:
            android_vc = int(vc_match.group(1))
            print(f"[+] Extracted compiled APK versionCode: {android_vc}")
        vn_match = re.search(r"versionName='([^']+)'", aapt_res.stdout)
        if vn_match:
            app_v = vn_match.group(1)
            print(f"[+] Extracted compiled APK versionName: {app_v}")
    except Exception as e:
        print(f"[!] Warning extracting APK metadata: {e}")

version_data = {
    "app_name": "nust_student_portal",
    "version": app_v,
    "android_version_code": android_vc,
    "build_number": str(build_time),
    "release_notes": "معمارية Local-First: تشغيل التطبيق بالكامل بدون إنترنت، حفظ محلي دائم للجداول والمحاضرات والإعلانات، ومعاينة أوفلاين فورية للمستندات.",
    "apk_url": "https://mohadarati.vercel.app/Mohadarati.apk",
    "deployed_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
}
for target_dir in [BUILD_WEB, WEB_SRC]:
    v_path = os.path.join(target_dir, "version.json")
    with open(v_path, "w", encoding="utf-8") as f:
        json.dump(version_data, f, indent=2)
print(f"[+] Injected build_number: {build_time} into version.json")

src_idx = os.path.join(WEB_SRC, "index.html")
dst_idx = os.path.join(BUILD_WEB, "index.html")
if os.path.exists(src_idx):
    with open(src_idx, "r", encoding="utf-8") as f:
        content = f.read()
    import re
    content = content.replace('<base href="$FLUTTER_BASE_HREF">', '<base href="/">')
    content = content.replace('<base href="/mohadarati/">', '<base href="/">')
    content = re.sub(r'src="flutter_bootstrap\.js(?:\?v=\d+)?"', f'src="flutter_bootstrap.js?v={build_time}"', content)
    with open(dst_idx, "w", encoding="utf-8") as f:
        f.write(content)
    print(f"[+] Synced and updated index.html with base href='/' and flutter_bootstrap.js?v={build_time}")

fb_path = os.path.join(BUILD_WEB, "flutter_bootstrap.js")
if os.path.exists(fb_path):
    with open(fb_path, "r", encoding="utf-8") as f:
        fb_content = f.read()
    import re
    fb_content = re.sub(r'"mainJsPath":\s*"main\.dart\.js(?:\?v=\d+)?"', f'"mainJsPath":"main.dart.js?v={build_time}"', fb_content)
    if 'canvasKitBaseUrl: "canvaskit/"' not in fb_content:
        fb_content = fb_content.replace(
            '_flutter.loader.load({',
            '_flutter.loader.load({\n  config: {\n    canvasKitBaseUrl: "canvaskit/"\n  },'
        )
    with open(fb_path, "w", encoding="utf-8") as f:
        f.write(fb_content)
    print(f"[+] Injected cache buster & local canvasKitBaseUrl into flutter_bootstrap.js: ?v={build_time}")

# 5. Git setup in build/web
git_dir = os.path.join(BUILD_WEB, ".git")
if not os.path.exists(git_dir):
    subprocess.run(["git", "init", "-b", "main"], cwd=BUILD_WEB, check=True)
    subprocess.run(["git", "config", "user.name", "مجتبى عواد"], cwd=BUILD_WEB, check=True)
    subprocess.run(["git", "config", "user.email", "mgtba2003mgtba@gmail.com"], cwd=BUILD_WEB, check=True)
    if token:
        remote_url = f"https://x-access-token:{token}@github.com/mgtba2003mgtba-boop/mohadarati.git"
        subprocess.run(["git", "remote", "add", "origin", remote_url], cwd=BUILD_WEB, check=True)
    else:
        subprocess.run(["git", "remote", "add", "origin", "https://github.com/mgtba2003mgtba-boop/mohadarati.git"], cwd=BUILD_WEB, check=True)
elif token:
    remote_url = f"https://x-access-token:{token}@github.com/mgtba2003mgtba-boop/mohadarati.git"
    subprocess.run(["git", "remote", "set-url", "origin", remote_url], cwd=BUILD_WEB, check=True)

subprocess.run(["git", "config", "http.postBuffer", "524288000"], cwd=BUILD_WEB, check=True)
subprocess.run(["git", "config", "http.version", "HTTP/1.1"], cwd=BUILD_WEB, check=True)

# 6. Fetch / reset origin main to ensure clean sync
print("[*] Staging and committing build/web...")
subprocess.run(["git", "add", "-A"], cwd=BUILD_WEB, check=True)
subprocess.run(["git", "commit", "-m", "deploy: pwa & ios auto-update, cache-busting, syllabus and representative features"], cwd=BUILD_WEB)

# 7. Push to mohadarati
print("[*] Pushing to mohadarati main...")
res = subprocess.run(["git", "push", "-u", "origin", "main", "--force"], cwd=BUILD_WEB, capture_output=True, text=True)
print("Push stdout:", res.stdout)
print("Push stderr:", res.stderr)
if res.returncode == 0:
    print("[SUCCESS] Deployed successfully to mohadarati repository! Vercel will update in seconds.")
else:
    print(f"[ERROR] Failed to push: {res.returncode}")
