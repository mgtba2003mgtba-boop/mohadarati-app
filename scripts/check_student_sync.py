import sys
import json
import base64
import urllib.request

sys.stdout.reconfigure(encoding='utf-8')

# Read 954 vector cache students
with open('C:/Users/Almustaqbal/Downloads/nnnnnnn/vector_cache.json', encoding='utf-8') as f:
    vc = json.load(f)

vc_students = vc.get('students', [])
print(f"Vector cache students count: {len(vc_students)}")

PORTAL_URL = 'https://mrubdzgcjofjwirkdfwo.supabase.co'
PORTAL_KEY = base64.b64decode('ZXlKaGJHY2lPaUpJVXpJMU5pSXNJblI1Y0NJNklrcFhWQ0o5LmV5SnBjM01pT2lKemRYQmhZbUZ6WlNJc0luSmxaaUk2SW0xeWRXSmtlbWRqYW05bWFuZHBjbXRrWm5kdklpd2ljbTlzWlNJNkltRnViMjRpTENKcFlYUWlPakUzT1RFNE1qQTROVEVzSW1WNGNDSTZNakV3TnpNNU5qZzFNWDAucy1fVW9KaVJnYi04NF81V2hyUXQwY1NtRkVDVTduczF5Q3ZrMFhHQ0FCUQ==').decode('utf-8')

headers_portal = {
    'apikey': PORTAL_KEY,
    'Authorization': f'Bearer {PORTAL_KEY}'
}

# Fetch all app_users
# Supabase pagination limit defaults to 1000
req = urllib.request.Request(
    f'{PORTAL_URL}/rest/v1/app_users?select=id,student_id,name,department,stage,section,photo_url,role',
    headers=headers_portal
)
with urllib.request.urlopen(req) as resp:
    portal_users = json.loads(resp.read().decode('utf-8'))

print(f"Portal DB app_users count: {len(portal_users)}")

portal_by_sid = {u['student_id']: u for u in portal_users if u.get('student_id')}
vc_sids = {s['id']: s for s in vc_students}

missing_in_portal = [s for s in vc_students if s['id'] not in portal_by_sid]
print(f"VC students missing in app_users: {len(missing_in_portal)}")
if missing_in_portal:
    print("Sample missing in app_users:")
    for s in missing_in_portal[:5]:
        print(f"  ID: {s.get('id')} | Name: {s.get('name')} | Dept: {s.get('department')} | Stage: {s.get('stage')}")

# Check photo_url sync
photos_to_update = []
for sid, vc_stud in vc_sids.items():
    if sid in portal_by_sid:
        p_user = portal_by_sid[sid]
        vc_photo = vc_stud.get('photoUrl') or vc_stud.get('photo_url')
        if vc_photo and not p_user.get('photo_url'):
            photos_to_update.append((p_user['id'], sid, vc_photo))

print(f"Portal users missing photo_url that exist in vector cache: {len(photos_to_update)}")
