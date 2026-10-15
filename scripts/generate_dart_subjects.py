import json
import sys

if hasattr(sys.stdout, 'reconfigure'):
    sys.stdout.reconfigure(encoding='utf-8')

with open('structured_comp_courses.json', 'r', encoding='utf-8') as f:
    items = json.load(f)

# Deduplicate
seen = set()
unique = []
for it in items:
    # Handle the duplicate Arabic MTU1001
    code = it['code']
    name = it['name']
    if code == 'MTU1001' and '1' in name:
        continue # skip the duplicate "اللغة العربية 1" since "اللغة العربية" is already there
    k = (it['stageId'], it['semester'], code)
    if k not in seen:
        seen.add(k)
        unique.append(it)

print(f"Total Unique Courses: {len(unique)}")

# Map to standard stage names and clean up
dart_entries = []
for it in unique:
    cid = it['id']
    name = it['name']
    dept_id = it['departmentId']
    dept_name = it['departmentName']
    stg_id = it['stageId']
    stg_name = it['stageName']
    sem = it['semester']
    code = it['code']
    units = it['units']
    hours = it['creditHours']
    ctype = it['type']
    
    dart = f"""    SubjectModel(
      id: '{cid}',
      name: '{name}',
      departmentId: '{dept_id}',
      departmentName: '{dept_name}',
      stageId: '{stg_id}',
      stageName: '{stg_name}',
      semester: {sem},
      code: '{code}',
      units: {units},
      creditHours: {hours},
      type: '{ctype}',
    ),"""
    dart_entries.append(dart)

with open('dart_comp_subjects.txt', 'w', encoding='utf-8') as out:
    out.write("\n".join(dart_entries))

print("Wrote dart entries to dart_comp_subjects.txt")
