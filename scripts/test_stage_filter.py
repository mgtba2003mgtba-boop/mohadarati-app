import os
import sys
import json
import urllib.request
import urllib.parse
import urllib.error

if hasattr(sys.stdout, 'reconfigure'):
    sys.stdout.reconfigure(encoding='utf-8')

att_url = 'https://rlupqsmqwvidmwrvqrcc.supabase.co/rest/v1'
att_key = 'sb_publishable_sJM5JiXGzn-jif8EYqXC-g_5_HdADJ4'

portal_url = 'https://mrubdzgcjofjwirkdfwo.supabase.co/rest/v1'
portal_key = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im1ydWJkemdjam9mandpcmtkZndvIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTE4MjA4NTEsImV4cCI6MjEwNzM5Njg1MX0.s-_UoJiRgb-84_5WhrQt0cSmFECU7ns1yCvk0XGCABQ'

# Test 1: Fetch Stage 2 students from attendance server
q_dept = urllib.parse.quote('هندسة تقنيات الأجهزة الطبية')
# In PostgREST, 'in' filter is: stage=in.(%D8%A7%D9%84%D8%B3%D9%86%D8%A9%20%D8%A7%D9%84%D8%AB%D8%A7%D9%86%D9%8A%D8%A9,%D8%A7%D9%84%D9%85%D8%B1%D8%AD%D9%84%D8%A9%20%D8%A7%D9%84%D8%AB%D8%A7%D9%86%D9%8A%D8%A9)
s2_list = ['السنة الثانية', 'المرحلة الثانية']
s2_param = '(' + ','.join([f'"{s}"' for s in s2_list]) + ')'
url_s2 = f'{att_url}/students?department=eq.{q_dept}&stage=in.{urllib.parse.quote(s2_param)}&select=id,name,department,stage,section&limit=5'

req = urllib.request.Request(url_s2, headers={'apikey': att_key, 'Authorization': f'Bearer {att_key}'})
try:
    with urllib.request.urlopen(req) as resp:
        data = json.loads(resp.read().decode('utf-8'))
        print(f"Attendance Stage 2 Students found: {len(data)}")
        for s in data:
            print(f"  {s['id']} | {s['name']} | {s['stage']} | Section: {s['section']}")
except Exception as e:
    print("Error fetching S2:", e)

# Test 2: Fetch Stage 3 students from attendance server
s3_list = ['السنة الثالثة', 'المرحلة الثالثة']
s3_param = '(' + ','.join([f'"{s}"' for s in s3_list]) + ')'
url_s3 = f'{att_url}/students?department=eq.{q_dept}&stage=in.{urllib.parse.quote(s3_param)}&select=id,name,department,stage,section&limit=5'

req = urllib.request.Request(url_s3, headers={'apikey': att_key, 'Authorization': f'Bearer {att_key}'})
try:
    with urllib.request.urlopen(req) as resp:
        data = json.loads(resp.read().decode('utf-8'))
        print(f"\nAttendance Stage 3 Students found: {len(data)}")
        for s in data:
            print(f"  {s['id']} | {s['name']} | {s['stage']} | Section: {s['section']}")
except Exception as e:
    print("Error fetching S3:", e)
