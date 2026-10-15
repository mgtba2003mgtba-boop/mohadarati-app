/// نموذج بيانات الجدول الدراسي والامتحاني
class ScheduleModel {
  final String id;
  final String title;
  final String type; // 'lectures' (محاضرات أسبوعية) أو 'exams' (جدول امتحانات)
  final String department;
  final String stage;
  final String section; // 'ALL', 'A', 'B', 'C', etc.
  final String? fileUrl; // رابط صورة الجدول أو ملف الـ PDF
  final String? fileName;
  final String? uploaderName;
  final String? uploaderId;
  final int? telegramMessageId;
  final DateTime createdAt;
  final List<ScheduleItemModel> items;

  ScheduleModel({
    required this.id,
    required this.title,
    required this.type,
    required this.department,
    required this.stage,
    this.section = 'ALL',
    this.fileUrl,
    this.fileName,
    this.uploaderName,
    this.uploaderId,
    this.telegramMessageId,
    required this.createdAt,
    this.items = const [],
  });

  bool get isExam => type == 'exams';
  bool get hasFile => fileUrl != null && fileUrl!.trim().isNotEmpty;
  bool get isUnified => section == 'ALL' || section.trim().isEmpty;
  String get sectionLabel => (section.isEmpty || section == 'ALL') ? 'شعبة A' : 'شعبة $section';
  String get formattedDate => '${createdAt.year}/${createdAt.month.toString().padLeft(2, '0')}/${createdAt.day.toString().padLeft(2, '0')}';
  bool get isImage {
    if (!hasFile) return false;
    final lower = fileUrl!.toLowerCase();
    return lower.endsWith('.png') ||
        lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.webp') ||
        lower.contains('image');
  }

  bool get isPdf {
    if (!hasFile) return false;
    final lower = fileUrl!.toLowerCase();
    final nameLower = (fileName ?? '').toLowerCase();
    return lower.endsWith('.pdf') || nameLower.endsWith('.pdf') || lower.contains('pdf');
  }

  factory ScheduleModel.fromJson(Map<String, dynamic> json) {
    var rawItems = json['items'];
    List<ScheduleItemModel> parsedItems = [];
    if (rawItems is List) {
      parsedItems = rawItems
          .whereType<Map<String, dynamic>>()
          .map((i) => ScheduleItemModel.fromJson(i))
          .toList();
    }

    final rawContent = json['content']?.toString() ?? '';
    final tgMatch = RegExp(r'\[TG_MSG_ID:(\d+)\]').firstMatch(rawContent);
    final parsedTgId = tgMatch != null ? int.tryParse(tgMatch.group(1) ?? '') : null;

    String sec = json['section']?.toString() ?? '';
    if (sec.isEmpty || sec == 'null') {
      final secMatch = RegExp(r'\[SECTION:([A-Za-z0-9_]+)\]').firstMatch(rawContent);
      sec = secMatch?.group(1) ?? 'ALL';
    }

    return ScheduleModel(
      id: json['id']?.toString() ?? '',
      title: json['title'] ?? 'جدول دراسي',
      type: json['type'] ?? 'lectures',
      department: json['department'] ?? 'ALL',
      stage: json['stage'] ?? 'ALL',
      section: sec,
      fileUrl: json['file_url'] ?? json['image_url'],
      fileName: json['file_name'],
      uploaderName: json['uploader_name'] ?? json['author_name'],
      uploaderId: json['uploader_id'] ?? json['author_id'],
      telegramMessageId: parsedTgId ?? int.tryParse(json['telegram_message_id']?.toString() ?? ''),
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at']) ?? DateTime.now()
          : DateTime.now(),
      items: parsedItems,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'type': type,
      'department': department,
      'stage': stage,
      'section': section,
      'file_url': fileUrl,
      'file_name': fileName,
      'uploader_name': uploaderName,
      'uploader_id': uploaderId,
      'telegram_message_id': telegramMessageId,
      'created_at': createdAt.toIso8601String(),
      'items': items.map((i) => i.toJson()).toList(),
    };
  }
}

/// بند أو حصة داخل الجدول الدراسي السريع
class ScheduleItemModel {
  final String day; // الأحد، الإثنين، إلخ
  final String time; // 08:30 - 10:30
  final String subjectName;
  final String hall; // القاعة / المختبر
  final String? professor;

  ScheduleItemModel({
    required this.day,
    required this.time,
    required this.subjectName,
    required this.hall,
    this.professor,
  });

  factory ScheduleItemModel.fromJson(Map<String, dynamic> json) {
    return ScheduleItemModel(
      day: json['day'] ?? '',
      time: json['time'] ?? '',
      subjectName: json['subject_name'] ?? '',
      hall: json['hall'] ?? '',
      professor: json['professor'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'day': day,
      'time': time,
      'subject_name': subjectName,
      'hall': hall,
      'professor': professor,
    };
  }
}
