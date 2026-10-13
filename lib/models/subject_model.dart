/// نموذج المادة والمقرر الدراسي الرسمي من نظام البصمة
class SubjectModel {
  final String id;
  final String name;
  final String departmentId; // e.g. DEP_MED, DEP_COMP, DEP_CYBER
  final String departmentName; // e.g. هندسة تقنيات الأجهزة الطبية
  final String stageId; // e.g. MED_STAGE_1
  final String stageName; // e.g. المرحلة الأولى
  final int semester; // 1 or 2

  const SubjectModel({
    required this.id,
    required this.name,
    required this.departmentId,
    required this.departmentName,
    required this.stageId,
    required this.stageName,
    required this.semester,
  });

  factory SubjectModel.fromJson(Map<String, dynamic> json) {
    return SubjectModel(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      departmentId: json['departmentId']?.toString() ?? json['department_id']?.toString() ?? '',
      departmentName: json['departmentName']?.toString() ?? '',
      stageId: json['stageId']?.toString() ?? json['stage_id']?.toString() ?? '',
      stageName: json['stageName']?.toString() ?? '',
      semester: json['semester'] is int
          ? json['semester']
          : (json['semester_id']?.toString().contains('SEM_2') == true ? 2 : 1),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'departmentId': departmentId,
      'departmentName': departmentName,
      'stageId': stageId,
      'stageName': stageName,
      'semester': semester,
    };
  }

  @override
  String toString() => name;
}
