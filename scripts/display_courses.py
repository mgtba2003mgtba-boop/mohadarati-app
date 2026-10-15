import json
import sys

if hasattr(sys.stdout, 'reconfigure'):
    sys.stdout.reconfigure(encoding='utf-8')

with open('scratch_courses_props.json', 'r', encoding='utf-8') as f:
    props = json.load(f)

courses = props.get('courses', [])
print(f"Total courses found: {len(courses)}")

levels = {}
for c in courses:
    lvl = c.get('level') or c.get('year') or 'Unknown'
    sem = c.get('semester') or 'Unknown'
    key = f"Level {lvl} - Semester {sem}"
    if key not in levels:
        levels[key] = []
    levels[key].append({
        'code': c.get('code'),
        'name': c.get('name'),
        'units': c.get('total_units') or c.get('credit_hours'),
        'credit_hours': c.get('credit_hours'),
        'total_units': c.get('total_units'),
        'type': c.get('type')
    })

for k in sorted(levels.keys()):
    print("=" * 50)
    print(k, f"({len(levels[k])} courses):")
    for item in levels[k]:
        code = item['code']
        name = item['name']
        units = item['units']
        hrs = item['credit_hours']
        t = item['type']
        print(f"  [{code}] {name} | وحدات: {units} (ساعات: {hrs}) | {t}")
