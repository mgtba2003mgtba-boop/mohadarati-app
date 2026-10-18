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
      studentId == 'ST-NUST-001630760-413' ||
      name.contains('مجتبى');
  @deprecated
  bool get isProfessor => false;
  bool get isRepresentative => role == AppConstants.roleRepresentative;
  bool get isStudent => role == AppConstants.roleStudent;

  bool get canManageLectures => isAdmin || (isRepresentative && canPublishLectures);
  bool get canManageAnnouncements => isAdmin || (isRepresentative && canPublishAnnouncements);
  bool get canPromoteUsers => isAdmin;
  bool get canManageCourses => isAdmin || isRepresentative || canManageLectures;

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
      photoUrl: json['photo_url']?.toString(),
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
      'pin_code': pinCode,
      'role': role,
      'can_publish_lectures': canPublishLectures,
      'can_publish_announcements': canPublishAnnouncements,
      'is_approved': isApproved,
      'photo_url': photoUrl,
      'semester': semester,
    };
  }
}
