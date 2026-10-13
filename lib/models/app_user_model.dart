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
  });

  bool get isAdmin => role == AppConstants.roleAdmin;
  @deprecated
  bool get isProfessor => false;
  bool get isRepresentative => role == AppConstants.roleRepresentative;
  bool get isStudent => role == AppConstants.roleStudent;

  bool get canManageLectures => isAdmin || (isRepresentative && canPublishLectures);
  bool get canManageAnnouncements => isAdmin || (isRepresentative && canPublishAnnouncements);
  bool get canPromoteUsers => isAdmin;
  bool get canManageCourses => isAdmin || isRepresentative || canManageLectures;

  String get roleLabel => AppConstants.getRoleLabel(role);

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
      stage: json['stage']?.toString() ?? '',
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
    };
  }
}
