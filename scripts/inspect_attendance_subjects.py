import sys
import json
import urllib.request

sys.stdout.reconfigure(encoding='utf-8')

ATT_URL = 'https://rlupqsmqwvidmwrvqrcc.supabase.co'
ATT_KEY = 'sb_publishable_sJM5JiXGzn-jif8EYqXC-g_5_HdADJ4'
headers = {'apikey': ATT_KEY, 'Authorization': f'Bearer {ATT_KEY}'}

req = urllib.request.Request(f'{ATT_URL}/rest/v1/attendance_records?select=subject_name,subject_id', headers=headers)
with urllib.request.urlopen(req) as resp:
    records = json.loads(resp.read().decode('utf-8'))

distinct = {}
for r in records:
    name = r.get('subject_name')
    sid = r.get('subject_id')
    distinct[(name, sid)] = distinct.get((name, sid), 0) + 1

print(f'Total records: {len(records)}')
print(f'Distinct subject pairs: {len(distinct)}')
for (name, sid), count in sorted(distinct.items(), key=lambda x: -x[1]):
    print(f'Count: {count:4d} | Name: "{name}" | ID: {sid}')
