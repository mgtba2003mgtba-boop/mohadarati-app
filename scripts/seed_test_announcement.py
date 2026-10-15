import os
import sys
import json
import urllib.request
import urllib.error

if hasattr(sys.stdout, 'reconfigure'):
    sys.stdout.reconfigure(encoding='utf-8')

url = 'https://mrubdzgcjofjwirkdfwo.supabase.co/rest/v1/announcements'
key = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im1ydWJkemdjam9mandpcmtkZndvIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTE4MjA4NTEsImV4cCI6MjEwNzM5Njg1MX0.s-_UoJiRgb-84_5WhrQt0cSmFECU7ns1yCvk0XGCABQ'

# First delete the garbled test row if it exists
delete_url = f"{url}?id=eq.31182a65-b410-4145-9d3c-a916c3be2f15"
del_req = urllib.request.Request(
    delete_url,
    headers={
        'apikey': key,
        'Authorization': f'Bearer {key}',
    },
    method='DELETE'
)
try:
    with urllib.request.urlopen(del_req) as resp:
        print("Deleted old test row:", resp.status)
except Exception as e:
    print("Delete note:", e)

# Now insert proper UTF-8 announcement
payload = {
    'title': 'تبليغ موعد كويز مادة معمارية الحاسوب',
    'content': 'أعزائي طلبة شعبة A، سيكون موعد الكويز الأول في مادة معمارية الحاسوب يوم الأحد القادم في القاعة 3. يرجى مراجعة المحاضرات الأولى والثانية. [SECTION:A]',
    'author_id': 'REP_CS_STG1_SECA',
    'author_name': 'ممثل الشعبة (أحمد)',
    'author_role': 'representative',
    'department': 'هندسة تقنيات الحاسوب',
    'stage': 'المرحلة الأولى',
    'category': 'academic',
    'subject_name': 'معمارية الحاسوب',
    'is_pinned': True
}

data = json.dumps(payload, ensure_ascii=False).encode('utf-8')
req = urllib.request.Request(
    url,
    data=data,
    headers={
        'apikey': key,
        'Authorization': f'Bearer {key}',
        'Content-Type': 'application/json; charset=utf-8',
        'Prefer': 'return=representation'
    }
)

try:
    with urllib.request.urlopen(req) as resp:
        res = json.loads(resp.read().decode('utf-8'))
        print('SUCCESS INSERTED:')
        print(json.dumps(res, indent=2, ensure_ascii=False))
except urllib.error.HTTPError as e:
    print('HTTP ERROR:', e.code, e.read().decode('utf-8'))
except Exception as e:
    print('ERROR:', e)
