import json
import sys

if hasattr(sys.stdout, 'reconfigure'):
    sys.stdout.reconfigure(encoding='utf-8')

with open('scratch_courses_props.json', 'r', encoding='utf-8') as f:
    props = json.load(f)

courses = props.get('courses', [])
bachelor = [c for c in courses if c.get('program_id') == 243]

print(f"Total Bachelor (بكالوريوس) Courses: {len(bachelor)}")

# Organize by stage based on course code or year
# CET1xxx = First Stage
# CET2xxx = Second Stage
# CET3xxx = Third Stage
# CET4xxx = Fourth Stage
# MTU1xxx = General university courses

stages = {
    "المرحلة الأولى": {"الفصل الأول": [], "الفصل الثاني": []},
    "المرحلة الثانية": {"الفصل الأول": [], "الفصل الثاني": []},
    "المرحلة الثالثة": {"الفصل الأول": [], "الفصل الثاني": []},
    "المرحلة الرابعة": {"الفصل الأول": [], "الفصل الثاني": []},
    "غير محدد": {"الفصل الأول": [], "الفصل الثاني": []}
}

for c in bachelor:
    code = c.get('code') or ''
    name = c.get('name') or ''
    units = c.get('total_units') or c.get('credit_hours')
    hours = c.get('credit_hours')
    sem_num = c.get('semester')
    sem_key = "الفصل الأول" if sem_num == 1 else "الفصل الثاني"
    
    # Determine stage
    if code.startswith("CET1") or code in ["MTU1001", "MTU1006"]:
        stg_key = "المرحلة الأولى"
    elif code.startswith("CET2") or code in ["MTU1003", "MTU1007", "MTU1009"]:
        stg_key = "المرحلة الثانية"
    elif code.startswith("CET3"):
        stg_key = "المرحلة الثالثة"
    elif code.startswith("CET4") or code in ["MTU1088", "CET5109"]:
        stg_key = "المرحلة الرابعة"
    else:
        # Fallback to year or level
        yr = c.get('year')
        lvl = c.get('level')
        if yr == 1 or lvl == 'beginner': stg_key = "المرحلة الأولى"
        elif yr == 2 or (lvl == 'intermediate' and sem_num == 1): stg_key = "المرحلة الثانية"
        elif yr == 3: stg_key = "المرحلة الثالثة"
        elif yr == 4 or lvl == 'advanced': stg_key = "المرحلة الرابعة"
        else: stg_key = "غير محدد"

    stages[stg_key][sem_key].append({
        'code': code,
        'name': name,
        'units': units,
        'hours': hours,
        'type': c.get('type')
    })

for stg, sems in stages.items():
    print("=" * 60)
    print(f"🎓 {stg}:")
    for sem, items in sems.items():
        print(f"  📌 {sem} ({len(items)} مواد):")
        for it in items:
            print(f"     - [{it['code']}] {it['name']} | الوحدات: {it['units']} | الساعات: {it['hours']}")
