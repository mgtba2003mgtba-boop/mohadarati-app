import 'dart:convert';

/// نموذج التخصيص والاستبدال للمقررات الدراسية (الاسم المعروض، الرمز الأكاديمي، وحالة الإخفاء)
/// مع الحفاظ الدائم على الاسم الأصلي لنظام البصمة الجامعي لمنع تيتيم أي محاضرات تاريخية
class CourseOverrideModel {
  final String originalName; // الاسم المرجعي الأصلي الثابت لنظام البصمة
  final String displayName; // الاسم المعروض المخصص في واجهة التطبيق
  final String? customCode; // الرمز المخصص للمادة (مثال: CET1101)
  final bool isHidden; // هل المقرر مخفي عن الطلاب العاديين؟
  final String department; // القسم الأكاديمي
  final String stage; // المرحلة الأكاديمية
  final int semester; // الفصل الدراسي (1 أو 2)
  final DateTime? updatedAt;
  final String? updatedBy;

  const CourseOverrideModel({
    required this.originalName,
    required this.displayName,
    this.customCode,
    this.isHidden = false,
    required this.department,
    required this.stage,
    this.semester = 1,
    this.updatedAt,
    this.updatedBy,
  });

  CourseOverrideModel copyWith({
    String? originalName,
    String? displayName,
    String? customCode,
    bool? isHidden,
    String? department,
    String? stage,
    int? semester,
    DateTime? updatedAt,
    String? updatedBy,
  }) {
    return CourseOverrideModel(
      originalName: originalName ?? this.originalName,
      displayName: displayName ?? this.displayName,
      customCode: customCode ?? this.customCode,
      isHidden: isHidden ?? this.isHidden,
      department: department ?? this.department,
      stage: stage ?? this.stage,
      semester: semester ?? this.semester,
      updatedAt: updatedAt ?? this.updatedAt,
      updatedBy: updatedBy ?? this.updatedBy,
    );
  }

  factory CourseOverrideModel.fromJson(Map<String, dynamic> json) {
    return CourseOverrideModel(
      originalName: json['original_name']?.toString() ?? json['originalName']?.toString() ?? '',
      displayName: json['display_name']?.toString() ?? json['displayName']?.toString() ?? json['original_name']?.toString() ?? '',
      customCode: json['custom_code']?.toString() ?? json['customCode']?.toString(),
      isHidden: json['is_hidden'] == true || json['isHidden'] == true,
      department: json['department']?.toString() ?? '',
      stage: json['stage']?.toString() ?? '',
      semester: json['semester'] is int ? json['semester'] : int.tryParse(json['semester']?.toString() ?? '1') ?? 1,
      updatedAt: json['updated_at'] != null ? DateTime.tryParse(json['updated_at'].toString()) : null,
      updatedBy: json['updated_by']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'original_name': originalName,
      'display_name': displayName,
      'custom_code': customCode,
      'is_hidden': isHidden,
      'department': department,
      'stage': stage,
      'semester': semester,
      if (updatedAt != null) 'updated_at': updatedAt!.toIso8601String(),
      if (updatedBy != null) 'updated_by': updatedBy,
    };
  }

  static CourseOverrideModel? fromAnnouncementContent(String content) {
    try {
      const tag = '[COURSE_OVERRIDE_V1]';
      if (!content.contains(tag)) return null;
      final jsonStr = content.substring(content.indexOf(tag) + tag.length).trim();
      final map = jsonDecode(jsonStr);
      if (map is Map<String, dynamic>) {
        return CourseOverrideModel.fromJson(map);
      }
    } catch (_) {}
    return null;
  }
}
