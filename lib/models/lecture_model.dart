import '../core/constants/app_constants.dart';

class LectureModel {
  final String id;
  final String title;
  final String subjectName;
  final String? subjectCode;
  final String department;
  final String stage;
  final String section; // 'ALL', 'A', 'B', 'C', etc.
  final int semester; // 1 or 2
  final String type; // 'theory' or 'practical'
  final String driveUrl;
  final String? description;
  final String? professorName;
  final String uploaderId;
  final String uploaderName;
  final String uploaderRole;
  final int downloadCount;
  final DateTime createdAt;

  final int? telegramChannelId;
  final int? telegramMessageId;
  final String? telegramFileId;
  final String? fileName;
  final int? fileSizeBytes;
  final String? mimeType;
  final int? durationSeconds;
  final String? thumbnailUrl;

  LectureModel({
    required this.id,
    required this.title,
    required this.subjectName,
    this.subjectCode,
    required this.department,
    required this.stage,
    this.section = 'ALL',
    this.semester = 1,
    this.type = 'theory',
    required this.driveUrl,
    this.description,
    this.professorName,
    required this.uploaderId,
    required this.uploaderName,
    this.uploaderRole = 'representative',
    this.downloadCount = 0,
    required this.createdAt,
    this.telegramChannelId,
    this.telegramMessageId,
    this.telegramFileId,
    this.fileName,
    this.fileSizeBytes,
    this.mimeType,
    this.durationSeconds,
    this.thumbnailUrl,
  });

  bool get isPractical => type == 'practical';
  String get typeLabel => isPractical ? 'مختبر وعملي' : 'نظري';

  /// الوصف النظيف للعرض بدون وسوم النظام الداخلية
  String get displayDescription {
    if (description == null) return '';
    return description!
        .replaceAll(RegExp(r'\[SECTION:[^\]]+\]'), '')
        .trim();
  }

  /// هل تتوفر المحاضرة عبر سحابة تيليجرام
  bool get hasTelegramMedia =>
      (telegramMessageId != null) ||
      (telegramFileId != null && telegramFileId!.isNotEmpty) ||
      driveUrl.contains('api.telegram.org');

  /// هل تتوفر المحاضرة عبر رابط Google Drive خارجي
  bool get hasDriveUrl =>
      driveUrl.trim().isNotEmpty &&
      driveUrl != 'telegram' &&
      !driveUrl.contains('api.telegram.org');

  /// رابط البث المباشر أو المعاينة السحابية
  String? get streamUrl {
    final cleanDrive = driveUrl.trim();
    if (cleanDrive.isNotEmpty && cleanDrive != 'telegram') {
      return cleanDrive;
    }
    if (telegramMessageId != null) {
      return '${AppConstants.telegramStreamerBaseUrl}/api/lecture/$telegramMessageId/stream';
    }
    return null;
  }

  /// رابط التحميل المباشر من السحابة
  String? get downloadUrl {
    final cleanDrive = driveUrl.trim();
    if (cleanDrive.isNotEmpty && cleanDrive != 'telegram') {
      return cleanDrive;
    }
    if (telegramMessageId != null) {
      return '${AppConstants.telegramStreamerBaseUrl}/api/lecture/$telegramMessageId/download';
    }
    return null;
  }

  /// حجم الملف بصيغة مقروءة (MB أو KB)
  String get formattedFileSize {
    if (fileSizeBytes == null || fileSizeBytes == 0) return '';
    final bytes = fileSizeBytes!;
    if (bytes >= 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    } else if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    } else {
      return '${(bytes / 1024).toStringAsFixed(0)} KB';
    }
  }

  /// استخراج معرّف ملف Google Drive وتوليد رابط معاينة مباشر إن أمكن
  String get cleanDriveViewUrl {
    final trimmed = driveUrl.trim();
    if (trimmed.contains('drive.google.com/file/d/')) {
      final regExp = RegExp(r'file/d/([a-zA-Z0-9_-]+)');
      final match = regExp.firstMatch(trimmed);
      if (match != null && match.groupCount >= 1) {
        final fileId = match.group(1);
        return 'https://drive.google.com/file/d/$fileId/view';
      }
    }
    return trimmed;
  }

  factory LectureModel.fromJson(Map<String, dynamic> json) {
    DateTime created = DateTime.now();
    if (json['created_at'] != null) {
      try {
        created = DateTime.parse(json['created_at'].toString());
      } catch (_) {}
    }

    final rawDesc = json['description']?.toString() ?? '';
    String sec = json['section']?.toString() ?? '';
    if (sec.isEmpty || sec == 'null') {
      final match = RegExp(r'\[SECTION:([A-Za-z0-9_]+)\]').firstMatch(rawDesc);
      sec = match?.group(1) ?? 'ALL';
    }

    return LectureModel(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      subjectName: json['subject_name']?.toString() ?? '',
      subjectCode: json['subject_code']?.toString(),
      department: json['department']?.toString() ?? '',
      stage: json['stage']?.toString() ?? '',
      section: sec,
      semester: int.tryParse(json['semester']?.toString() ?? '1') ?? 1,
      type: json['type']?.toString() ?? 'theory',
      driveUrl: json['drive_url']?.toString() ?? '',
      description: rawDesc.isEmpty ? null : rawDesc,
      professorName: json['professor_name']?.toString(),
      uploaderId: json['uploader_id']?.toString() ?? '',
      uploaderName: json['uploader_name']?.toString() ?? '',
      uploaderRole: json['uploader_role']?.toString() ?? 'representative',
      downloadCount: int.tryParse(json['download_count']?.toString() ?? '0') ?? 0,
      createdAt: created,
      telegramChannelId: int.tryParse(json['telegram_channel_id']?.toString() ?? ''),
      telegramMessageId: int.tryParse(json['telegram_message_id']?.toString() ?? ''),
      telegramFileId: json['telegram_file_id']?.toString(),
      fileName: json['file_name']?.toString(),
      fileSizeBytes: int.tryParse(json['file_size_bytes']?.toString() ?? ''),
      mimeType: json['mime_type']?.toString(),
      durationSeconds: int.tryParse(json['duration_seconds']?.toString() ?? ''),
      thumbnailUrl: json['thumbnail_url']?.toString(),
    );
  }

  /// تحويل المحاضرة إلى صيغة تخزين الكاش المحلي مع الحفاظ التام على المعرف الفريد وتاريخ الإنشاء
  Map<String, dynamic> toCacheJson() {
    final map = toJson();
    if (id.isNotEmpty) map['id'] = id;
    map['created_at'] = createdAt.toIso8601String();
    return map;
  }

  Map<String, dynamic> toJson() {
    String descWithSection = (description ?? '').trim();
    if (!descWithSection.contains('[SECTION:')) {
      descWithSection = '$descWithSection [SECTION:$section]'.trim();
    }

    final map = <String, dynamic>{
      'title': title,
      'subject_name': subjectName,
      'subject_code': subjectCode,
      'department': department,
      'stage': stage,
      'semester': semester,
      'type': type,
      'drive_url': driveUrl,
      'description': descWithSection,
      'uploader_id': uploaderId,
      'uploader_name': uploaderName,
      'uploader_role': uploaderRole,
      'telegram_channel_id': telegramChannelId,
      'telegram_message_id': telegramMessageId,
      'telegram_file_id': telegramFileId,
      'file_name': fileName,
      'file_size_bytes': fileSizeBytes,
      'mime_type': mimeType,
      'duration_seconds': durationSeconds,
      'thumbnail_url': thumbnailUrl,
    };

    if (id.isNotEmpty) {
      map['id'] = id;
    }
    return map;
  }

  /// تحويل المحاضرة إلى حمولة قاعدة البيانات السحابية مع ضمان خلوها من أي أعمدة غير موجودة (مثل section)
  Map<String, dynamic> toDbJson() {
    final map = toJson();
    map.remove('section'); // جدول lectures لا يحتوي على عمود section في Supabase
    String desc = (map['description']?.toString() ?? '').trim();
    if (!desc.contains('[SECTION:')) {
      desc = '$desc [SECTION:$section]'.trim();
    }
    map['description'] = desc;
    map['stage'] = AppConstants.normalizeStage(stage);
    return map;
  }
}
