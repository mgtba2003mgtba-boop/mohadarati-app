import requests
import json

key = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im1ydWJkemdjam9mandpcmtkZndvIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTE4MjA4NTEsImV4cCI6MjEwNzM5Njg1MX0.s-_UoJiRgb-84_5WhrQt0cSmFECU7ns1yCvk0XGCABQ'
headers = {
    'apikey': key,
    'Authorization': f'Bearer {key}',
    'Content-Type': 'application/json',
    'Prefer': 'return=representation'
}

# 1. Update lectures with "السنة الثانية" -> "المرحلة الثانية"
r1 = requests.patch(
    'https://mrubdzgcjofjwirkdfwo.supabase.co/rest/v1/lectures?stage=eq.السنة الثانية',
    headers=headers,
    json={'stage': 'المرحلة الثانية'}
)
print("Updated lectures (السنة الثانية -> المرحلة الثانية):", len(r1.json()) if isinstance(r1.json(), list) else r1.json())

# 2. Update lectures with "السنة الثالثة" -> "المرحلة الثالثة"
r2 = requests.patch(
    'https://mrubdzgcjofjwirkdfwo.supabase.co/rest/v1/lectures?stage=eq.السنة الثالثة',
    headers=headers,
    json={'stage': 'المرحلة الثالثة'}
)
print("Updated lectures (السنة الثالثة -> المرحلة الثالثة):", len(r2.json()) if isinstance(r2.json(), list) else r2.json())

# 3. Update announcements with "السنة الثانية" -> "المرحلة الثانية"
r3 = requests.patch(
    'https://mrubdzgcjofjwirkdfwo.supabase.co/rest/v1/announcements?stage=eq.السنة الثانية',
    headers=headers,
    json={'stage': 'المرحلة الثانية'}
)
print("Updated announcements (السنة الثانية -> المرحلة الثانية):", len(r3.json()) if isinstance(r3.json(), list) else r3.json())

# 4. Update announcements with "السنة الثالثة" -> "المرحلة الثالثة"
r4 = requests.patch(
    'https://mrubdzgcjofjwirkdfwo.supabase.co/rest/v1/announcements?stage=eq.السنة الثالثة',
    headers=headers,
    json={'stage': 'المرحلة الثالثة'}
)
print("Updated announcements (السنة الثالثة -> المرحلة الثالثة):", len(r4.json()) if isinstance(r4.json(), list) else r4.json())

# 5. Fix subject_name for "الأجهزة الطبية المختبريه" -> "الأجهزة الطبية المختبرية" in lectures
r5 = requests.patch(
    'https://mrubdzgcjofjwirkdfwo.supabase.co/rest/v1/lectures?subject_name=eq.الأجهزة الطبية المختبريه',
    headers=headers,
    json={'subject_name': 'الأجهزة الطبية المختبرية'}
)
print("Normalized subject_name in lectures:", len(r5.json()) if isinstance(r5.json(), list) else r5.json())
