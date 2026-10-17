import urllib.request
import json
import base64
import sys

sys.stdout.reconfigure(encoding='utf-8')

key = base64.b64decode('ZXlKaGJHY2lPaUpJVXpJMU5pSXNJblI1Y0NJNklrcFhWQ0o5LmV5SnBjM01pT2lKemRYQmhZbUZ6WlNJc0luSmxaaUk2SW0xeWRXSmtlbWRqYW05bWFuZHBjbXRrWm5kdklpd2ljbTlzWlNJNkltRnViMjRpTENKcFlYUWlPakUzT1RFNE1qQTROVEVzSW1WNGNDSTZNakV3TnpNNU5qZzFNWDAucy1fVW9KaVJnYi04NF81V2hyUXQwY1NtRkVDVTduczF5Q3ZrMFhHQ0FCUQ==').decode()
req = urllib.request.Request(
    'https://mrubdzgcjofjwirkdfwo.supabase.co/rest/v1/announcements?select=*',
    headers={'apikey': key, 'Authorization': 'Bearer ' + key}
)

with urllib.request.urlopen(req) as resp:
    data = json.loads(resp.read().decode('utf-8'))
    print(f"Total count: {len(data)}")
    for x in data:
        subj = x.get('subject_name')
        title = x.get('title')
        content = (x.get('content') or '')[:40]
        print(f"id={x.get('id')} | title={title} | subj={subj} | dept={x.get('department')} | stage={x.get('stage')} | content={content}")
