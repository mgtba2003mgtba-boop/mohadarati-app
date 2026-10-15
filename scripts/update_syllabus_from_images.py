import re

comp_subjects = [
    # Stage 1 - Semester 1
    ('CET1101', 'مبادىء الرقمية', 'المرحلة الأولى', 1, 1, 6, 4, 'required'),
    ('CET1102', 'مباديء الهندسية الكهربائية', 'المرحلة الأولى', 1, 1, 6, 4, 'required'),
    ('CET1103', 'الرياضيات I', 'المرحلة الأولى', 1, 1, 5, 3, 'required'),
    ('CET1104', 'الرسم الهندسي', 'المرحلة الأولى', 1, 1, 5, 3, 'required'),
    ('CET1105', 'الورش الهندسية', 'المرحلة الأولى', 1, 1, 6, 4, 'required'),
    ('MTU1002', 'اللغة الإنكليزية ١', 'المرحلة الأولى', 1, 1, 2, 2, 'required'),
    # Stage 1 - Semester 2
    ('CET1201', 'الانظمة الرقمية', 'المرحلة الأولى', 1, 2, 6, 4, 'required'),
    ('CET1202', 'الدوائر الكهربائية', 'المرحلة الأولى', 1, 2, 6, 4, 'required'),
    ('CET1203', 'أساسيات البرمجة', 'المرحلة الأولى', 1, 2, 6, 4, 'required'),
    ('CET1204', 'الرياضيات II', 'المرحلة الأولى', 1, 2, 5, 3, 'required'),
    ('MTU1006', 'الديمقراطية و حقوق الانسان', 'المرحلة الأولى', 1, 2, 2, 2, 'required'),
    ('MTU1001', 'اللغة العربية ١', 'المرحلة الأولى', 1, 2, 2, 2, 'required'),
    ('MTU1004', 'اساسيات الحاسوب', 'المرحلة الأولى', 1, 2, 3, 2, 'required'),

    # Stage 2 - Semester 1 (Three)
    ('CET2101', 'الرياضيات الهندسية', 'المرحلة الثانية', 2, 1, 5, 3, 'required'),
    ('CET2102', 'البرمجة الكيانية', 'المرحلة الثانية', 2, 1, 6, 4, 'required'),
    ('CET2103', 'تركيب الحاسوب وتطبيقاته', 'المرحلة الثانية', 2, 1, 6, 4, 'required'),
    ('CET2104', 'مباديء الالكترونيك', 'المرحلة الثانية', 2, 1, 6, 4, 'required'),
    ('CET2105', 'اسس الاتصالات', 'المرحلة الثانية', 2, 1, 5, 4, 'required'),
    ('MTU1003', 'اللغة الإنكليزية ٢', 'المرحلة الثانية', 2, 1, 2, 2, 'required'),
    ('MTU1007', 'جرائم نظام البعث في العراق', 'المرحلة الثانية', 2, 1, 2, 2, 'required'),
    # Stage 2 - Semester 2 (Four)
    ('CET2201', 'الرياضيات الهندسية المتقدمة', 'المرحلة الثانية', 2, 2, 5, 3, 'required'),
    ('CET2202', 'البرمجة بلغة بايثون', 'المرحلة الثانية', 2, 2, 6, 4, 'required'),
    ('CET2203', 'المعالجات الدقيقة', 'المرحلة الثانية', 2, 2, 6, 4, 'required'),
    ('CET2204', 'الاتصالات التماثلية', 'المرحلة الثانية', 2, 2, 5, 4, 'required'),
    ('CET2205', 'الدوائر الالكترونية', 'المرحلة الثانية', 2, 2, 6, 4, 'required'),
    ('CET2206', 'الاجهزة و القياس', 'المرحلة الثانية', 2, 2, 5, 3, 'required'),
    ('MTU1009', 'اللغة العربية ٢', 'المرحلة الثانية', 2, 2, 2, 2, 'required'),

    # Stage 3 - Semester 1 (Five)
    ('CET3101', 'انظمة التشغيل', 'المرحلة الثالثة', 3, 1, 6, 4, 'required'),
    ('CET3102', 'اسس هندسة السيطرة', 'المرحلة الثالثة', 3, 1, 5, 4, 'required'),
    ('CET3103', 'معالجة الاشارة الرقمية', 'المرحلة الثالثة', 3, 1, 5, 4, 'required'),
    ('CET3104', 'المسيطرات الدقيقة', 'المرحلة الثالثة', 3, 1, 6, 4, 'required'),
    ('CET3105', 'الاتصالات الرقمية', 'المرحلة الثالثة', 3, 1, 5, 4, 'required'),
    ('CET3106', 'أنظمة الزمن الحقيقي [اختياري]', 'المرحلة الثالثة', 3, 1, 5, 3, 'elective'),
    ('CET3107', 'الحوسبة المتوازية [اختياري]', 'المرحلة الثالثة', 3, 1, 5, 3, 'elective'),
    # Stage 3 - Semester 2 (Six)
    ('CET3201', 'انظمة السيطره المتقدمة', 'المرحلة الثالثة', 3, 2, 5, 4, 'required'),
    ('CET3202', 'اساسيات شبكات الحاسوب', 'المرحلة الثالثة', 3, 2, 6, 4, 'required'),
    ('CET3203', 'قواعد البيانات', 'المرحلة الثالثة', 3, 2, 6, 4, 'required'),
    ('CET3204', 'التحليلات الهندسية', 'المرحلة الثالثة', 3, 2, 5, 3, 'required'),
    ('CET3205', 'اتصالات البيانات', 'المرحلة الثالثة', 3, 2, 5, 4, 'required'),
    ('CET3206', 'معالجة الصور الرقمية [اختياري]', 'المرحلة الثالثة', 3, 2, 5, 3, 'elective'),
    ('CET3207', 'أساسيات انترنت الأشياء [اختياري]', 'المرحلة الثالثة', 3, 2, 5, 3, 'elective'),

    # Stage 4 - Semester 1 (Seven)
    ('CET4101', 'نظرية المعلومات و الترميز', 'المرحلة الرابعة', 4, 1, 5, 3, 'required'),
    ('CET4102', 'بروتوكولات شبكات الحاسوب', 'المرحلة الرابعة', 4, 1, 6, 4, 'required'),
    ('CET4103', 'الاتصالات المتنقلة', 'المرحلة الرابعة', 4, 1, 5, 4, 'required'),
    ('CET4104', 'الادارة الهندسية', 'المرحلة الرابعة', 4, 1, 4, 3, 'required'),
    ('MTU1008', 'اخلاقيات المهنة', 'المرحلة الرابعة', 4, 1, 2, 2, 'required'),
    ('CET4105', 'الذكاء الاصطناعي [اختياري]', 'المرحلة الرابعة', 4, 1, 5, 3, 'elective'),
    ('CET4106', 'تصميم المواقع الالكترونية [اختياري]', 'المرحلة الرابعة', 4, 1, 5, 3, 'elective'),
    ('CET4107', 'أنظمة الحوسبة الموزعة [اختياري]', 'المرحلة الرابعة', 4, 1, 5, 3, 'elective'),
    # Stage 4 - Semester 2 (Eight)
    ('CET4201', 'اتصالات الالياف البصرية', 'المرحلة الرابعة', 4, 2, 5, 4, 'required'),
    ('CET4202', 'تكنولوجيا الحاسوب المتقدم', 'المرحلة الرابعة', 4, 2, 5, 4, 'required'),
    ('CET4203', 'أمنية الشبكات والامن السيبراني', 'المرحلة الرابعة', 4, 2, 6, 4, 'required'),
    ('CET4204', 'الحوسبة السحابية', 'المرحلة الرابعة', 4, 2, 5, 3, 'required'),
    ('CET4205', 'مشروع', 'المرحلة الرابعة', 4, 2, 6, 6, 'required'),
    ('CET4206', 'نظم الحوسبة القابلة لإعادة التكوين [اختياري]', 'المرحلة الرابعة', 4, 2, 5, 3, 'elective'),
    ('CET4207', 'شبكات المستشعرات اللاسلكية [اختياري]', 'المرحلة الرابعة', 4, 2, 5, 3, 'elective'),
    ('CET4208', 'خوارزميات التحسين [اختياري]', 'المرحلة الرابعة', 4, 2, 5, 3, 'elective'),
]

dart_items = []
for code, name, stage_name, stage_num, sem, units, hours, item_type in comp_subjects:
    item_id = f"SUB_COMP_L{stage_num}_S{sem}_{code}"
    stage_id = f"COMP_STAGE_{stage_num}"
    item_dart = f"""    SubjectModel(
      id: '{item_id}',
      name: '{name}',
      departmentId: 'DEP_COMP',
      departmentName: 'هندسة تقنيات الحاسوب',
      stageId: '{stage_id}',
      stageName: '{stage_name}',
      semester: {sem},
      code: '{code}',
      units: {units},
      creditHours: {hours},
      type: '{item_type}',
    ),"""
    dart_items.append(item_dart)

new_comp_dart = "\n".join(dart_items)

with open(r'c:\Users\Almustaqbal\Downloads\تطبيق الحضور\lib\core\constants\biometric_subjects.dart', 'r', encoding='utf-8') as f:
    content = f.read()

# Locate from first SubjectModel to SUB_CYBER_L1_S1_CSEC1101
cyber_marker = "SubjectModel(\n      id: 'SUB_CYBER_L1_S1_CSEC1101',"
if cyber_marker not in content:
    # Try alternate spacing
    cyber_marker_idx = content.find("SUB_CYBER_L1_S1_CSEC1101")
    # find preceding SubjectModel(
    start_cyber = content.rfind("SubjectModel(", 0, cyber_marker_idx)
else:
    start_cyber = content.find(cyber_marker)

header_marker = "static const List<SubjectModel> allSubjects = [\n"
start_comp = content.find(header_marker) + len(header_marker)

updated_content = content[:start_comp] + new_comp_dart + "\n    " + content[start_cyber:]

with open(r'c:\Users\Almustaqbal\Downloads\تطبيق الحضور\lib\core\constants\biometric_subjects.dart', 'w', encoding='utf-8') as f:
    f.write(updated_content)

print("[+] Successfully updated biometric_subjects.dart with official 57 syllabus subjects!")

with open(r'c:\Users\Almustaqbal\Downloads\تطبيق الحضور\lib\core\constants\biometric_subjects.dart', 'r', encoding='utf-8') as f:
    text = f.read()
matches = re.findall(r"id:\s*'([^']+)'", text)
comp = [m for m in matches if 'SUB_COMP' in m]
cyber = [m for m in matches if 'SUB_CYBER' in m]
med = [m for m in matches if 'SUB_MED' in m]
print(f"Total: {len(matches)} | Comp: {len(comp)} | Cyber: {len(cyber)} | Med: {len(med)}")
