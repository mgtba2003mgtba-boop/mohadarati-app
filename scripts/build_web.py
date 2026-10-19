import os
import subprocess
import sys

PROJECT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
FLUTTER_BIN = r"D:\flutter\bin\flutter.bat"

print(f"[*] Project root: {PROJECT_ROOT}")

# 1. Clean previous subst if any
subprocess.run(["subst", "Z:", "/D"], capture_output=True)

# 2. Map virtual drive Z: to avoid non-ASCII path encoding issues
res_subst = subprocess.run(["subst", "Z:", PROJECT_ROOT], capture_output=True, text=True)
if res_subst.returncode != 0:
    print(f"[!] Warning: subst failed: {res_subst.stderr}")

target_cwd = "Z:" if os.path.exists("Z:") else PROJECT_ROOT
print(f"[*] Building web in: {target_cwd}")

try:
    cmd = [FLUTTER_BIN, "build", "web", "--release", "--no-tree-shake-icons"]
    res = subprocess.run(cmd, cwd=target_cwd)
    if res.returncode != 0:
        print(f"[!] Build failed with exit code: {res.returncode}")
        sys.exit(res.returncode)
    print("[+] Flutter Web build completed successfully!")
finally:
    subprocess.run(["subst", "Z:", "/D"], capture_output=True)
