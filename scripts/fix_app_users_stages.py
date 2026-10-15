import os
import sys
import json
import urllib.request
import urllib.parse
import urllib.error

if hasattr(sys.stdout, 'reconfigure'):
    sys.stdout.reconfigure(encoding='utf-8')

portal_url = 'https://mrubdzgcjofjwirkdfwo.supabase.co/rest/v1'
portal_key = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im1ydWJkemdjam9mandpcmtkZndvIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTE4MjA4NTEsImV4cCI6MjEwNzM5Njg1MX0.s-_UoJiRgb-84_5WhrQt0cSmFECU7ns1yCvk0XGCABQ'

headers = {
    'apikey': portal_key,
    'Authorization': f'Bearer {portal_key}',
    'Content-Type': 'application/json',
    'Prefer': 'return=representation'
}

# 1. Update 'السنة الثانية' -> 'المرحلة الثانية'
url_s2 = f"{portal_url}/app_users?stage=eq.{urllib.parse.quote('السنة الثانية')}"
data_s2 = json.dumps({'stage': 'المرحلة الثانية'}).encode('utf-8')
req_s2 = urllib.request.Request(url_s2, data=data_s2, headers=headers, method='PATCH')
try:
    with urllib.request.urlopen(req_s2) as resp:
        res = json.loads(resp.read().decode('utf-8'))
        print(f"Updated {len(res)} students from 'السنة الثانية' to 'المرحلة الثانية'")
except Exception as e:
    print("Error updating S2:", e)

# 2. Update 'السنة الثالثة' -> 'المرحلة الثالثة'
url_s3 = f"{portal_url}/app_users?stage=eq.{urllib.parse.quote('السنة الثالثة')}"
data_s3 = json.dumps({'stage': 'المرحلة الثالثة'}).encode('utf-8')
req_s3 = urllib.request.Request(url_s3, data=data_s3, headers=headers, method='PATCH')
try:
    with urllib.request.urlopen(req_s3) as resp:
        res = json.loads(resp.read().decode('utf-8'))
        print(f"Updated {len(res)} students from 'السنة الثالثة' to 'المرحلة الثالثة'")
except Exception as e:
    print("Error updating S3:", e)

# Check student ST-NUST-0013414835-876 specifically:
url_check = f"{portal_url}/app_users?student_id=eq.ST-NUST-0013414835-876"
req_check = urllib.request.Request(url_check, headers={'apikey': portal_key, 'Authorization': f'Bearer {portal_key}'})
with urllib.request.urlopen(req_check) as resp:
    data = json.loads(resp.read().decode('utf-8'))
    print("\nVerified student ST-NUST-0013414835-876:")
    print(json.dumps(data, indent=2, ensure_ascii=False))
