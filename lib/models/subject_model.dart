/// نموذج المادة والمقرر الدراسي الرسمي من نظام البصمة
class SubjectModel {
  final String id;
  final String name;
  final String departmentId; // e.g. DEP_MED, DEP_COMP, DEP_CYBER
  final String departmentName; // e.g. هندسة تقنيات الأجهزة الطبية
  final String stageId; // e.g. MED_STAGE_1
  final String stageName; // e.g. المرحلة الأولى
  final int semester; // 1 or 2
  final String? code; // e.g. CET1101, MTU1001
  final int? units; // e.g. 6, 5
  final int? creditHours; // e.g. 4, 3
  final String? type; // required, elective, general

  const SubjectModel({
    required this.id,
    required this.name,
    required this.departmentId,
    required this.departmentName,
    required this.stageId,
    required this.stageName,
    required this.semester,
    this.code,
    this.units,
    this.creditHours,
    this.type,
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
      code: json['code']?.toString(),
      units: json['units'] is int ? json['units'] : int.tryParse(json['units']?.toString() ?? ''),
      creditHours: json['creditHours'] is int ? json['creditHours'] : int.tryParse(json['credit_hours']?.toString() ?? ''),
      type: json['type']?.toString(),
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
      if (code != null) 'code': code,
      if (units != null) 'units': units,
      if (creditHours != null) 'creditHours': creditHours,
      if (type != null) 'type': type,
    };
  }

  @override
  String toString() => name;
}
