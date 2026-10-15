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

# 3. Ensure mobileconfig and media
for f in ["mohadarati.mobileconfig", "ios_install_guide.gif", "ios_install_guide.mp4"]:
    src_f = os.path.join(WEB_SRC, f)
    if os.path.exists(src_f):
        shutil.copy2(src_f, os.path.join(BUILD_WEB, f))
        print(f"[+] Copied {f}")

# 4. Ensure index.html has base href="/"
idx_path = os.path.join(BUILD_WEB, "index.html")
if os.path.exists(idx_path):
    with open(idx_path, "r", encoding="utf-8") as f:
        content = f.read()
    if '<base href="/mohadarati/">' in content:
        content = content.replace('<base href="/mohadarati/">', '<base href="/">')
        with open(idx_path, "w", encoding="utf-8") as f:
            f.write(content)
        print("[+] Fixed base href in index.html to /")

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
subprocess.run(["git", "commit", "-m", "deploy: update Computer Engineering official syllabus across 8 semesters and section privacy features"], cwd=BUILD_WEB)

# 7. Push to mohadarati
print("[*] Pushing to mohadarati main...")
res = subprocess.run(["git", "push", "-u", "origin", "main", "--force"], cwd=BUILD_WEB, capture_output=True, text=True)
print("Push stdout:", res.stdout)
print("Push stderr:", res.stderr)
if res.returncode == 0:
    print("[SUCCESS] Deployed successfully to mohadarati repository! Vercel will update in seconds.")
else:
    print(f"[ERROR] Failed to push: {res.returncode}")
