import sys
import json
import re
import urllib.request

sys.stdout.reconfigure(encoding='utf-8')

ATT_URL = 'https://rlupqsmqwvidmwrvqrcc.supabase.co'
ATT_KEY = 'sb_publishable_sJM5JiXGzn-jif8EYqXC-g_5_HdADJ4'

headers = {
    'apikey': ATT_KEY,
    'Authorization': f'Bearer {ATT_KEY}',
    'Content-Type': 'application/json',
    'Prefer': 'resolution=merge-duplicates,return=representation'
}

# 1. Parse all 125 subjects from biometric_subjects.dart
with open('lib/core/constants/biometric_subjects.dart', encoding='utf-8') as f:
    text = f.read()

pattern = re.compile(
    r'SubjectModel\(\s*id:\s*[\x27\x22]([^\x27\x22]+)[\x27\x22],\s*name:\s*[\x27\x22]([^\x27\x22]+)[\x27\x22],\s*departmentId:\s*[\x27\x22]([^\x27\x22]+)[\x27\x22],\s*departmentName:\s*[\x27\x22]([^\x27\x22]+)[\x27\x22],\s*stageId:\s*[\x27\x22]([^\x27\x22]+)[\x27\x22],\s*stageName:\s*[\x27\x22]([^\x27\x22]+)[\x27\x22],\s*semester:\s*(\d+)',
    re.MULTILINE
)
dart_subjects = pattern.findall(text)
print(f"Extracted {len(dart_subjects)} canonical subjects from Mohadarati.")

# Build DB payload
subjects_to_upsert = []
for s in dart_subjects:
    subj_id, name, dept_id, dept_name, stage_id, stage_name, sem_str = s
    sem_id = f"{stage_id}_SEM_{sem_str}"
    subjects_to_upsert.append({
        'id': subj_id,
        'name': name,
        'department_id': dept_id,
        'stage_id': stage_id,
        'semester_id': sem_id,
    })

print(f"Upserting {len(subjects_to_upsert)} subjects to Supabase {ATT_URL}...")

# Upsert in batches of 25
batch_size = 25
total_upserted = 0
for i in range(0, len(subjects_to_upsert), batch_size):
    batch = subjects_to_upsert[i:i + batch_size]
    req = urllib.request.Request(
        f'{ATT_URL}/rest/v1/subjects',
        data=json.dumps(batch).encode('utf-8'),
        headers=headers,
        method='POST'
    )
    try:
        with urllib.request.urlopen(req) as resp:
            res = json.loads(resp.read().decode('utf-8'))
            total_upserted += len(res)
    except urllib.error.HTTPError as e:
        print(f"HTTPError on batch {i}: {e.code} - {e.read().decode('utf-8')}")
        sys.exit(1)

print(f"Successfully upserted {total_upserted} subjects into 'subjects' table.")

# 2. Update historical attendance_records
print("\nHarmonizing historical attendance_records...")
req_records = urllib.request.Request(
    f'{ATT_URL}/rest/v1/attendance_records?select=id,subject_id,subject_name',
    headers={'apikey': ATT_KEY, 'Authorization': f'Bearer {ATT_KEY}'}
)
with urllib.request.urlopen(req_records) as resp:
    records = json.loads(resp.read().decode('utf-8'))

canonical_by_id = {s['id']: s['name'] for s in subjects_to_upsert}
updates_needed = {}
for r in records:
    sid = r.get('subject_id')
    cur_name = r.get('subject_name')
    if sid and sid in canonical_by_id:
        canon_name = canonical_by_id[sid]
        if cur_name != canon_name:
            updates_needed[sid] = canon_name

print(f"Found {len(updates_needed)} subject categories needing attendance_records name harmonization:")
for sid, canon in updates_needed.items():
    print(f"  Fixing subject {sid} -> '{canon}'")
    url = f'{ATT_URL}/rest/v1/attendance_records?subject_id=eq.{sid}'
    patch_req = urllib.request.Request(
        url,
        data=json.dumps({'subject_name': canon}).encode('utf-8'),
        headers={
            'apikey': ATT_KEY,
            'Authorization': f'Bearer {ATT_KEY}',
            'Content-Type': 'application/json',
            'Prefer': 'return=representation'
        },
        method='PATCH'
    )
    with urllib.request.urlopen(patch_req) as resp:
        res = json.loads(resp.read().decode('utf-8'))
        print(f"    Updated {len(res)} attendance records for {sid}.")

print("\n--- Verification of attendance_records ---")
req_records2 = urllib.request.Request(
    f'{ATT_URL}/rest/v1/attendance_records?select=id,subject_id,subject_name',
    headers={'apikey': ATT_KEY, 'Authorization': f'Bearer {ATT_KEY}'}
)
with urllib.request.urlopen(req_records2) as resp:
    records2 = json.loads(resp.read().decode('utf-8'))

mismatches = 0
for r in records2:
    sid = r.get('subject_id')
    sname = r.get('subject_name')
    if sid in canonical_by_id and canonical_by_id[sid] != sname:
        mismatches += 1

print(f"Total attendance records: {len(records2)}. Remaining mismatches: {mismatches}")
