class AnnouncementModel {
  final String id;
  final String title;
  final String content;
  final String authorId;
  final String authorName;
  final String authorRole;
  final String department;
  final String stage;
  final String section; // 'ALL', 'A', 'B', 'C', etc.
  final String category;
  final bool isPinned;
  final String? imageUrl;
  final String? subjectName;
  final DateTime createdAt;

  AnnouncementModel({
    required this.id,
    required this.title,
    required this.content,
    required this.authorId,
    required this.authorName,
    required this.authorRole,
    this.department = 'ALL',
    this.stage = 'ALL',
    this.section = 'ALL',
    this.category = 'academic',
    this.isPinned = false,
    this.imageUrl,
    this.subjectName,
    required this.createdAt,
  });

  /// معرف رسالة تيليجرام المرتبطة بالمنشور إن وجد
  int? get telegramMessageId {
    final match = RegExp(r'\[TG_MSG_ID:(\d+)\]').firstMatch(content);
    if (match != null) {
      return int.tryParse(match.group(1) ?? '');
    }
    return null;
  }

  /// المحتوى النظيف للعرض بدون وسوم تيليجرام والنظام الداخلية
  String get displayContent {
    return content
        .replaceAll(RegExp(r'\[TG_MSG_ID:\d+\]'), '')
        .replaceAll('[SCHEDULE_TIMETABLE]', '')
        .replaceAll(RegExp(r'\[COURSE_REGISTRY:[^\]]+\]'), '')
        .replaceAll(RegExp(r'\[SECTION:[^\]]+\]'), '')
        .trim();
  }

  factory AnnouncementModel.fromJson(Map<String, dynamic> json) {
    DateTime created = DateTime.now();
    if (json['created_at'] != null) {
      try {
        created = DateTime.parse(json['created_at'].toString());
      } catch (_) {}
    }

    final rawContent = json['content']?.toString() ?? '';
    String sec = json['section']?.toString() ?? '';
    if (sec.isEmpty || sec == 'null') {
      final match = RegExp(r'\[SECTION:([A-Za-z0-9_]+)\]').firstMatch(rawContent);
      sec = match?.group(1) ?? 'ALL';
    }

    return AnnouncementModel(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      content: rawContent,
      authorId: json['author_id']?.toString() ?? '',
      authorName: json['author_name']?.toString() ?? 'إدارة الكلية',
      authorRole: json['author_role']?.toString() ?? 'admin',
      department: json['department']?.toString() ?? 'ALL',
      stage: json['stage']?.toString() ?? 'ALL',
      section: sec,
      category: json['category']?.toString() ?? 'academic',
      isPinned: json['is_pinned'] == true,
      imageUrl: json['image_url']?.toString(),
      subjectName: json['subject_name']?.toString(),
      createdAt: created,
    );
  }

  Map<String, dynamic> toJson() {
    String tagContent = content.trim();
    if (!tagContent.contains('[SECTION:')) {
      tagContent = '$tagContent [SECTION:$section]'.trim();
    }

    return {
      'title': title,
      'content': tagContent,
      'author_id': authorId,
      'author_name': authorName,
      'author_role': authorRole,
      'department': department,
      'stage': stage,
      'category': category,
      'is_pinned': isPinned,
      'image_url': imageUrl,
      'subject_name': subjectName,
    };
  }
}
