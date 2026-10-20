import os
import shutil
import subprocess

PROJECT_ROOT = r"c:\Users\Almustaqbal\Downloads\تطبيق الحضور"
BUILD_WEB = os.path.join(PROJECT_ROOT, "build", "web")
WEB_SRC = os.path.join(PROJECT_ROOT, "web")

# Read token from environment variable if provided
token = os.environ.get("GITHUB_TOKEN") or os.environ.get("VERCEL_DEPLOY_TOKEN")

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

# 3. Ensure static web files, mobileconfig, pdf_viewer, and media
for f in ["mohadarati.mobileconfig", "ios_install_guide.gif", "ios_install_guide.mp4", "pdf_viewer.html", "favicon.png", "manifest.json"]:
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

# 4. Generate dynamic version.json and update index.html
import json
import time
build_time = int(time.time())
version_data = {
    "app_name": "nust_student_portal",
    "version": "1.0.2",
    "build_number": str(build_time),
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
