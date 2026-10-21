import sys
import json
import re
import urllib.request

sys.stdout.reconfigure(encoding='utf-8')

# 1. Fetch remote subjects from rlupqsmqwvidmwrvqrcc
url = 'https://rlupqsmqwvidmwrvqrcc.supabase.co/rest/v1/subjects?select=*'
headers = {
    'apikey': 'sb_publishable_sJM5JiXGzn-jif8EYqXC-g_5_HdADJ4',
    'Authorization': 'Bearer sb_publishable_sJM5JiXGzn-jif8EYqXC-g_5_HdADJ4'
}
req = urllib.request.Request(url, headers=headers)
with urllib.request.urlopen(req) as resp:
    db_subjects = json.loads(resp.read().decode('utf-8'))

# 2. Extract subjects from biometric_subjects.dart
with open('lib/core/constants/biometric_subjects.dart', encoding='utf-8') as f:
    text = f.read()

pattern = re.compile(
    r'SubjectModel\(\s*id:\s*[\x27\x22]([^\x27\x22]+)[\x27\x22],\s*name:\s*[\x27\x22]([^\x27\x22]+)[\x27\x22],\s*departmentId:\s*[\x27\x22]([^\x27\x22]+)[\x27\x22],\s*departmentName:\s*[\x27\x22]([^\x27\x22]+)[\x27\x22],\s*stageId:\s*[\x27\x22]([^\x27\x22]+)[\x27\x22],\s*stageName:\s*[\x27\x22]([^\x27\x22]+)[\x27\x22],\s*semester:\s*(\d+)',
    re.MULTILINE
)
dart_subjects = pattern.findall(text)

print(f'DB subjects count: {len(db_subjects)}')
print(f'Dart subjects count: {len(dart_subjects)}')

db_by_id = {s['id']: s for s in db_subjects}
dart_by_id = {
    s[0]: {
        'name': s[1],
        'deptId': s[2],
        'deptName': s[3],
        'stageId': s[4],
        'stageName': s[5],
        'semester': int(s[6])
    }
    for s in dart_subjects
}

common_ids = set(db_by_id.keys()).intersection(set(dart_by_id.keys()))
db_only_ids = set(db_by_id.keys()) - set(dart_by_id.keys())
dart_only_ids = set(dart_by_id.keys()) - set(db_by_id.keys())

print(f'Common IDs: {len(common_ids)}')
print(f'DB only IDs: {len(db_only_ids)}')
print(f'Dart only IDs: {len(dart_only_ids)}')

name_diffs = []
for cid in sorted(common_ids):
    if db_by_id[cid]['name'] != dart_by_id[cid]['name']:
        name_diffs.append((cid, db_by_id[cid]['name'], dart_by_id[cid]['name']))

print(f'Name differences in common IDs: {len(name_diffs)}')
for diff in name_diffs[:25]:
    print(f'  ID: {diff[0]} | DB: "{diff[1]}" vs Dart: "{diff[2]}"')

if db_only_ids:
    print('DB only sample:', list(db_only_ids)[:5])
if dart_only_ids:
    print('Dart only sample:', list(dart_only_ids)[:5])
