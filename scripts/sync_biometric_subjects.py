import json
import urllib.request
import urllib.error
import sys

if hasattr(sys.stdout, 'reconfigure'):
    sys.stdout.reconfigure(encoding='utf-8')

SUPABASE_URL = "https://rlupqsmqwvidmwrvqrcc.supabase.co"
SUPABASE_KEY = "sb_publishable_sJM5JiXGzn-jif8EYqXC-g_5_HdADJ4"

headers = {
    "apikey": SUPABASE_KEY,
    "Authorization": f"Bearer {SUPABASE_KEY}",
    "Content-Type": "application/json",
    "Prefer": "return=minimal"
}

with open('structured_comp_courses.json', 'r', encoding='utf-8') as f:
    items = json.load(f)

# Deduplicate
seen = set()
unique = []
for it in items:
    code = it['code']
    name = it['name']
    if code == 'MTU1001' and '1' in name:
        continue
    k = (it['stageId'], it['semester'], code)
    if k not in seen:
        seen.add(k)
        unique.append(it)

print(f"Total Unique Courses to sync: {len(unique)}")

# Prepare clean database rows
insert_rows = []
for it in unique:
    code = it['code']
    name = it['name']
    
    # Extract stage number: 1, 2, 3, or 4
    if code.startswith("CET1") or code in ["MTU1001", "MTU1002", "MTU1004", "MTU1006"]:
        stg_num = 1
    elif code.startswith("CET2") or code in ["MTU1003", "MTU1007", "MTU1009"]:
        stg_num = 2
    elif code.startswith("CET3"):
        stg_num = 3
    else:
        stg_num = 4

    # Extract semester number: 1 or 2
    if code.startswith("CET") and len(code) >= 5 and code[4] == '2':
        sem_num = 2
    elif code in ["MTU1004", "MTU1006", "MTU1009"]:
        sem_num = 2
    else:
        sem_num = 1

    stage_id = f"COMP_STAGE_{stg_num}"
    semester_id = f"COMP_STAGE_{stg_num}_SEM_{sem_num}"
    subject_id = f"SUB_COMP_L{stg_num}_S{sem_num}_{code}"
    
    row = {
        "id": subject_id,
        "name": name,
        "department_id": "DEP_COMP",
        "stage_id": stage_id,
        "semester_id": semester_id
    }
    insert_rows.append(row)

# 1. Clear old DEP_COMP subjects
del_url = f"{SUPABASE_URL}/rest/v1/subjects?department_id=eq.DEP_COMP"
req_del = urllib.request.Request(del_url, headers=headers, method="DELETE")
try:
    with urllib.request.urlopen(req_del) as resp:
        print(f"[INFO] Cleared old DEP_COMP subjects: status {resp.status}")
except Exception as e:
    print(f"[WARN] Error deleting old subjects: {e}")

# 2. Insert clean subjects
chunk_size = 20
success_count = 0
for i in range(0, len(insert_rows), chunk_size):
    chunk = insert_rows[i:i + chunk_size]
    ins_url = f"{SUPABASE_URL}/rest/v1/subjects"
    data = json.dumps(chunk).encode('utf-8')
    req_ins = urllib.request.Request(ins_url, data=data, headers=headers, method="POST")
    try:
        with urllib.request.urlopen(req_ins) as resp:
            success_count += len(chunk)
            print(f"  Inserted chunk {i // chunk_size + 1}: {len(chunk)} courses (Total: {success_count}/{len(insert_rows)})")
    except urllib.error.HTTPError as e:
        print(f"[ERROR] Failed chunk: {e.read().decode('utf-8')}")
    except Exception as e:
        print(f"[ERROR] Failed chunk: {e}")

print("=" * 50)
print(f"[DONE] Successfully synchronized all {success_count}/{len(insert_rows)} Computer Engineering courses in Supabase Biometric DB!")
