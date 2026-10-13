class StudentModel {
  final String id;
  final String name;
  final String department;
  final String stage;
  final String? section;
  final String? telegramChatId;
  final String? photoUrl;
  final DateTime? registeredAt;
  final bool hasFace;

  StudentModel({
    required this.id,
    required this.name,
    required this.department,
    required this.stage,
    this.section,
    this.telegramChatId,
    this.photoUrl,
    this.registeredAt,
    this.hasFace = false,
  });

  factory StudentModel.fromJson(Map<String, dynamic> json) {
    final photo = json['photo_url'] as String?;
    final faceEmbedding = json['face_embedding'];
    final faceDesc = json['face_descriptor'];
    final bool hasFaceRegistered = (photo != null && photo.isNotEmpty) ||
        (faceEmbedding != null) ||
        (faceDesc != null);

    DateTime? regAt;
    if (json['registered_at'] != null) {
      try {
        regAt = DateTime.parse(json['registered_at'].toString());
      } catch (_) {}
    }

    return StudentModel(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      department: json['department']?.toString() ?? 'غير محدد',
      stage: json['stage']?.toString() ?? 'المرحلة الأولى',
      section: json['section']?.toString(),
      telegramChatId: json['telegram_chat_id']?.toString(),
      photoUrl: photo,
      registeredAt: regAt,
      hasFace: hasFaceRegistered,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'department': department,
      'stage': stage,
      'section': section,
      'telegram_chat_id': telegramChatId,
      'photo_url': photoUrl,
      'registered_at': registeredAt?.toIso8601String(),
    };
  }

  String get fullAcademicDetails {
    final parts = [department, stage];
    if (section != null && section!.isNotEmpty) {
      parts.add('شعبة ($section)');
    }
    return parts.join(' • ');
  }
}
