import re

# Read original biometric_subjects.dart
with open("lib/core/constants/biometric_subjects.dart", "r", encoding="utf-8") as f:
    content = f.read()

# Read new dart entries
with open("dart_comp_subjects.txt", "r", encoding="utf-8") as f:
    new_entries = f.read()

# The start marker is: static const List<SubjectModel> allSubjects = [
start_marker = "  static const List<SubjectModel> allSubjects = ["
# The end of DEP_COMP is right before the first DEP_CYBER entry:
# SubjectModel(\n      id: 'SUB_CYBER_L1_S1_CSEC1101',
end_marker = "    SubjectModel(\n      id: 'SUB_CYBER_L1_S1_CSEC1101',"

idx_start = content.find(start_marker)
if idx_start == -1:
    print("Start marker not found!")
    exit(1)

idx_start += len(start_marker) + 1 # right after the newline

idx_end = content.find(end_marker)
if idx_end == -1:
    print("End marker not found!")
    exit(1)

new_content = content[:idx_start] + new_entries + "\n" + content[idx_end:]

# Also let's check if findSubject helper exists, if not add it before closing brace
if "findSubject(" not in new_content:
    closing_marker = "  static Map<String, Map<String, List<String>>> buildCurriculumMap() {"
    helper_code = """  /// البحث عن مقرر دراسي بالاسم واسترجاع نموذجه شاملاً الكود وعدد الوحدات
  static SubjectModel? findSubject(
    String name, {
    String? department,
    String? stage,
  }) {
    final cleanName = name.trim().toLowerCase();
    for (final s in allSubjects) {
      if (s.name.trim().toLowerCase() == cleanName) {
        if (department != null && department != 'ALL') {
          final matchDept = s.departmentName == department ||
              s.departmentName.contains(department) ||
              department.contains(s.departmentName);
          if (!matchDept) continue;
        }
        if (stage != null && stage != 'ALL') {
          final matchStage = s.stageName == stage ||
              s.stageName.contains(stage) ||
              stage.contains(s.stageName);
          if (!matchStage) continue;
        }
        return s;
      }
    }
    // Fallback search by substring or code
    for (final s in allSubjects) {
      if (s.name.contains(name) || (s.code != null && s.code!.toLowerCase() == cleanName)) {
        return s;
      }
    }
    return null;
  }

"""
    idx_close = new_content.find(closing_marker)
    if idx_close != -1:
        new_content = new_content[:idx_close] + helper_code + new_content[idx_close:]

with open("lib/core/constants/biometric_subjects.dart", "w", encoding="utf-8") as f:
    f.write(new_content)

print("[SUCCESS] Updated lib/core/constants/biometric_subjects.dart successfully!")
