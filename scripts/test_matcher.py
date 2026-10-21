import sys
import re

sys.stdout.reconfigure(encoding='utf-8')

def norm(s):
    if not s: return ''
    s = s.strip().lower()
    for ch in ['\u064b', '\u064c', '\u064d', '\u064e', '\u064f', '\u0650', '\u0651', '\u0652', '\u0670', '\u0640']:
        s = s.replace(ch, '')
    for ch in ['أ', 'إ', 'آ', 'ٱ']:
        s = s.replace(ch, 'ا')
    s = s.replace('ة', 'ه').replace('ى', 'ي').replace('ؤ', 'و').replace('ئ', 'ي')
    s = re.sub(r'\[.*?\]', '', s).strip()
    s = re.sub(r'\(.*?\)', '', s).strip()
    return re.sub(r'\s+', ' ', s)

def matches(cand, targ):
    nc = norm(cand)
    nt = norm(targ)
    if not nc or not nt: return False
    return nc == nt or nc in nt or (len(nc) >= 4 and nt in nc)

recorded = [
    'أنظمة الليزر الطبية', 'مشروع التخرج II', 'الاتصالات الرقمية', 'الأجهزة العلاجية الطبية I',
    'المسيطر الدقيق', 'معالجة الإشارة الطبية الحيوية', 'نظم السيطرة', 'الحوسبة المتوازية [اختياري]',
    'أنظمة الزمن الحقيقي [اختياري]', 'أنظمة الحوسبة الموزعة [اختياري]', 'الادارة الهندسية',
    'المعالج الدقيق', 'الذكاء الاصطناعي [اختياري]'
]

with open('lib/core/constants/biometric_subjects.dart', encoding='utf-8') as f:
    text = f.read()
dart_subjects = re.findall(r'name:\s*[\x27\x22]([^\x27\x22]+)[\x27\x22]', text)

all_matched = True
for r in recorded:
    matched = [s for s in dart_subjects if matches(r, s)]
    if not matched:
        all_matched = False
        print(f"FAILED TO MATCH: '{r}'")
    else:
        print(f"Recorded: '{r}' -> Matched: {matched[0]}")

print(f"\nAll 13 subjects successfully matched: {all_matched}")
