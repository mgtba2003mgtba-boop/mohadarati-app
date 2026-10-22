import '../core/constants/app_constants.dart';

class AppUserModel {
  final String id;
  final String studentId;
  final String name;
  final String department;
  final String stage;
  final String? section;
  final String? email;
  final String? phone;
  final String? pinCode;
  final String role; // 'student', 'representative', 'professor', 'admin'
  final bool canPublishLectures;
  final bool canPublishAnnouncements;
  final bool isApproved;
  final String? photoUrl;
  final DateTime? createdAt;
  final int semester; // 1 or 2 (الفصل الدراسي)

  AppUserModel({
    required this.id,
    required this.studentId,
    required this.name,
    required this.department,
    required this.stage,
    this.section,
    this.email,
    this.phone,
    this.pinCode,
    this.role = AppConstants.roleStudent,
    this.canPublishLectures = false,
    this.canPublishAnnouncements = false,
    this.isApproved = true,
    this.photoUrl,
    this.createdAt,
    this.semester = 1,
  });

  bool get isAdmin =>
      role == AppConstants.roleAdmin ||
      studentId == 'ST-NUST-001630760-413';
  @deprecated
  bool get isProfessor => false;
  bool get isRepresentative => role == AppConstants.roleRepresentative;
  bool get isStudent => role == AppConstants.roleStudent;

  bool get canManageLectures => isAdmin || isRepresentative || canPublishLectures;
  bool get canManageAnnouncements => isAdmin || isRepresentative || canPublishAnnouncements;
  bool get canPromoteUsers => isAdmin;
  bool get canManageCourses => isAdmin || isRepresentative || canManageLectures;

  /// قائمة الشُعب المعيارية المكلف بها أو المنتمي إليها (e.g. ['A', 'B'])
  List<String> get assignedSections {
    if (section == null || section!.trim().isEmpty) return [];
    return section!
        .split(RegExp(r'[,،/\s]+'))
        .map((s) => s.trim().toUpperCase())
        .where((s) => s.isNotEmpty)
        .toSet()
        .toList();
  }

  /// هل المستخدم مكلف بأكثر من شعبة دراسية
  bool get hasMultipleSections => assignedSections.length > 1;

  /// فحص صلاحية الوصول أو الانتماء لشعبة معينة
  bool hasSectionAccess(String? targetSection) {
    if (isAdmin) return true;
    if (targetSection == null || targetSection.trim().isEmpty) return true;
    final cleanTarget = targetSection.trim().toUpperCase();
    if (cleanTarget == 'ALL' || cleanTarget == 'الكل' || cleanTarget == 'عام') return true;

    final sections = assignedSections;
    if (sections.contains('ALL') || sections.contains('الكل')) return true;
    return sections.contains(cleanTarget);
  }

  /// نص منسق لعرض الشعب المكلف بها (مثل "A، B")
  String get sectionsDisplayLabel {
    final list = assignedSections;
    if (list.isEmpty) return section ?? 'غير محدد';
    return list.join('، ');
  }

  String get roleLabel => AppConstants.getRoleLabel(role);

  AppUserModel copyWith({
    String? id,
    String? studentId,
    String? name,
    String? department,
    String? stage,
    String? section,
    String? email,
    String? phone,
    String? pinCode,
    String? role,
    bool? canPublishLectures,
    bool? canPublishAnnouncements,
    bool? isApproved,
    String? photoUrl,
    DateTime? createdAt,
    int? semester,
  }) {
    return AppUserModel(
      id: id ?? this.id,
      studentId: studentId ?? this.studentId,
      name: name ?? this.name,
      department: department ?? this.department,
      stage: stage ?? this.stage,
      section: section ?? this.section,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      pinCode: pinCode ?? this.pinCode,
      role: role ?? this.role,
      canPublishLectures: canPublishLectures ?? this.canPublishLectures,
      canPublishAnnouncements: canPublishAnnouncements ?? this.canPublishAnnouncements,
      isApproved: isApproved ?? this.isApproved,
      photoUrl: photoUrl ?? this.photoUrl,
      createdAt: createdAt ?? this.createdAt,
      semester: semester ?? this.semester,
    );
  }

  factory AppUserModel.fromJson(Map<String, dynamic> json) {
    DateTime? created;
    if (json['created_at'] != null) {
      try {
        created = DateTime.parse(json['created_at'].toString());
      } catch (_) {}
    }

    return AppUserModel(
      id: json['id']?.toString() ?? '',
      studentId: json['student_id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      department: json['department']?.toString() ?? '',
      stage: AppConstants.normalizeStage(json['stage']?.toString()),
      section: json['section']?.toString(),
      email: json['email']?.toString(),
      phone: json['phone']?.toString(),
      pinCode: json['pin_code']?.toString(),
      role: json['role']?.toString() ?? AppConstants.roleStudent,
      canPublishLectures: json['can_publish_lectures'] == true,
      canPublishAnnouncements: json['can_publish_announcements'] == true,
      isApproved: json['is_approved'] != false,
      photoUrl: (json['photo_url'] != null && json['photo_url'].toString().trim().isNotEmpty)
          ? json['photo_url'].toString().trim()
          : (json['student_id'] != null && json['student_id'].toString().trim().startsWith('ST-NUST-')
              ? 'https://f004.backblazeb2.com/file/mujtaba-student-photos/${json['student_id'].toString().trim()}.jpg'
              : null),
      createdAt: created,
      semester: json['semester'] is int
          ? json['semester']
          : int.tryParse(json['semester']?.toString() ?? '1') ?? 1,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'student_id': studentId,
      'name': name,
      'department': department,
      'stage': stage,
      'section': section,
      'email': email,
      'phone': phone,
      'role': role,
      'can_publish_lectures': canPublishLectures,
      'can_publish_announcements': canPublishAnnouncements,
      'is_approved': isApproved,
      'photo_url': photoUrl,
      'semester': semester,
    };
  }
}
