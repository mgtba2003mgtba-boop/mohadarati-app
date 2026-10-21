import sys
import re
import json

sys.stdout.reconfigure(encoding='utf-8')

# 1. Parse all 125 subjects from biometric_subjects.dart
with open('lib/core/constants/biometric_subjects.dart', encoding='utf-8') as f:
    text = f.read()

pattern = re.compile(
    r'SubjectModel\(\s*id:\s*[\x27\x22]([^\x27\x22]+)[\x27\x22],\s*name:\s*[\x27\x22]([^\x27\x22]+)[\x27\x22],\s*departmentId:\s*[\x27\x22]([^\x27\x22]+)[\x27\x22],\s*departmentName:\s*[\x27\x22]([^\x27\x22]+)[\x27\x22],\s*stageId:\s*[\x27\x22]([^\x27\x22]+)[\x27\x22],\s*stageName:\s*[\x27\x22]([^\x27\x22]+)[\x27\x22],\s*semester:\s*(\d+)',
    re.MULTILINE
)
dart_subjects = pattern.findall(text)
print(f"Extracted {len(dart_subjects)} subjects.")

ts_entries = []
for s in dart_subjects:
    subj_id, name, dept_id, dept_name, stage_id, stage_name, sem_str = s
    sem_id = f"{stage_id}_SEM_{sem_str}"
    # Escape quotes
    clean_name = name.replace("'", "\\'")
    ts_entries.append(
        f"      {{ id: '{subj_id}', name: '{clean_name}', departmentId: '{dept_id}', stageId: '{stage_id}', semesterId: '{sem_id}' }}"
    )

new_default_subjects_block = "    const defaultSubjects: Subject[] = [\n" + ",\n".join(ts_entries) + "\n    ];"

# 2. Read C:/Users/Almustaqbal/Downloads/nnnnnnn_repo/src/lib/db.ts
db_ts_path = 'C:/Users/Almustaqbal/Downloads/nnnnnnn_repo/src/lib/db.ts'
with open(db_ts_path, encoding='utf-8') as f:
    db_content = f.read()

# Replace the curriculum sync check to v3
old_sync_check = "localStorage.getItem('local_curriculum_v2_synced')"
new_sync_check = "localStorage.getItem('local_curriculum_v3_mohadarati_synced')"

if old_sync_check in db_content:
    db_content = db_content.replace(
        """  // Clear any old mock academic cache once to ensure clean sync with approved curriculum
  const isCurriculumSynced = localStorage.getItem('local_curriculum_v2_synced');
  if (!isCurriculumSynced) {
    localStorage.removeItem('local_stages');
    localStorage.removeItem('local_semesters');
    localStorage.removeItem('local_subjects');
    localStorage.setItem('local_curriculum_v2_synced', 'true');
  }""",
        """  // Clear any old mock academic cache once to ensure clean sync with approved Mohadarati curriculum
  const isCurriculumSynced = localStorage.getItem('local_curriculum_v3_mohadarati_synced');
  if (!isCurriculumSynced) {
    localStorage.removeItem('local_departments');
    localStorage.removeItem('local_stages');
    localStorage.removeItem('local_semesters');
    localStorage.removeItem('local_subjects');
    localStorage.setItem('local_curriculum_v3_mohadarati_synced', 'true');
  }"""
    )

# Replace defaultSubjects definition
# Find from `if (!localStorage.getItem('local_subjects')) {` to `localStorage.setItem('local_subjects', JSON.stringify(defaultSubjects));`
match = re.search(
    r"  if \(!localStorage\.getItem\('local_subjects'\)\) \{\s*const defaultSubjects: Subject\[\] = \[.*?\];\s*localStorage\.setItem\('local_subjects', JSON\.stringify\(defaultSubjects\)\);\s*\}",
    db_content,
    re.DOTALL
)

if not match:
    print("Could not find defaultSubjects block with regex!")
    sys.exit(1)

replacement = f"  if (!localStorage.getItem('local_subjects')) {{\n{new_default_subjects_block}\n    localStorage.setItem('local_subjects', JSON.stringify(defaultSubjects));\n  }}"
db_content = db_content[:match.start()] + replacement + db_content[match.end():]

with open(db_ts_path, 'w', encoding='utf-8') as f:
    f.write(db_content)

print(f"Successfully updated {db_ts_path} with all 125 canonical subjects and v3 cache buster!")
