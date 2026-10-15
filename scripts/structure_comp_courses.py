import json
import sys

if hasattr(sys.stdout, 'reconfigure'):
    sys.stdout.reconfigure(encoding='utf-8')

with open('scratch_courses_props.json', 'r', encoding='utf-8') as f:
    props = json.load(f)

courses = props.get('courses', [])
bachelor = [c for c in courses if c.get('program_id') == 243]

# Let's inspect all bachelor courses
structured = []
for c in bachelor:
    code = (c.get('code') or '').strip()
    name = (c.get('name') or '').strip()
    units = c.get('total_units') or c.get('credit_hours')
    hours = c.get('credit_hours')
    ctype = c.get('type')
    
    # Determine stage and semester from code or data
    # Format: CET<Stage><Semester><Number>
    stage_num = 1
    sem_num = 1
    
    if code.startswith("CET") and len(code) >= 5 and code[3:5].isdigit():
        stage_num = int(code[3])
        sem_num = int(code[4])
    elif code.startswith("MTU"):
        # MTU university requirements
        if code in ["MTU1001", "MTU1002"]:
            stage_num = 1; sem_num = 1
        elif code in ["MTU1004", "MTU1006"]:
            stage_num = 1; sem_num = 2
        elif code in ["MTU1003", "MTU1007"]:
            stage_num = 2; sem_num = 1
        elif code in ["MTU1009"]:
            stage_num = 2; sem_num = 2
        elif code in ["MTU1088"]:
            stage_num = 4; sem_num = 1
    elif code == "CET5109": # English for stage 4
        stage_num = 4; sem_num = 1

    stage_names = {
        1: "المرحلة الأولى",
        2: "المرحلة الثانية",
        3: "المرحلة الثالثة",
        4: "المرحلة الرابعة"
    }

    stage_name = stage_names.get(stage_num, f"المرحلة {stage_num}")
    
    structured.append({
        'id': f"SUB_COMP_L{stage_num}_S{sem_num}_{code}",
        'code': code,
        'name': name,
        'departmentId': 'DEP_COMP',
        'departmentName': 'هندسة تقنيات الحاسوب',
        'stageId': f"COMP_STAGE_{stage_num}",
        'stageName': stage_name,
        'semester': sem_num,
        'units': int(units) if units else None,
        'creditHours': int(hours) if hours else None,
        'type': ctype
    })

# Sort by stage, semester, code
structured.sort(key=lambda x: (x['stageId'], x['semester'], x['code']))

print(f"Total structured courses: {len(structured)}")
current_group = ""
for item in structured:
    grp = f"{item['stageName']} - الفصل {item['semester']}"
    if grp != current_group:
        current_group = grp
        print("\n" + "=" * 50)
        print(f"📚 {current_group}:")
    print(f"   [{item['code']}] {item['name']} | الوحدات: {item['units']} | الساعات: {item['creditHours']} | {item['type']}")

with open('structured_comp_courses.json', 'w', encoding='utf-8') as out:
    json.dump(structured, out, ensure_ascii=False, indent=2)
print("\nSaved to structured_comp_courses.json")
