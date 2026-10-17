import 'dart:convert';

/// نموذج تفاعل الطالب الأكاديمي مع التبليغ
class AnnouncementReaction {
  final String studentId;
  final String studentName;
  final String department;
  final String stage;
  final String section;
  final String reaction; // e.g. '👍', '❤️', '👏', '💡', '🔥'
  final DateTime createdAt;

  AnnouncementReaction({
    required this.studentId,
    required this.studentName,
    this.department = '',
    this.stage = '',
    this.section = '',
    required this.reaction,
    required this.createdAt,
  });

  factory AnnouncementReaction.fromJson(Map<String, dynamic> json) {
    DateTime time = DateTime.now();
    if (json['time'] != null) {
      try {
        time = DateTime.parse(json['time'].toString());
      } catch (_) {}
    }
    return AnnouncementReaction(
      studentId: json['id']?.toString() ?? '',
      studentName: json['name']?.toString() ?? 'طالب',
      department: json['dept']?.toString() ?? '',
      stage: json['stg']?.toString() ?? '',
      section: json['sec']?.toString() ?? '',
      reaction: json['r']?.toString() ?? '👍',
      createdAt: time,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': studentId,
      'name': studentName,
      'dept': department,
      'stg': stage,
      'sec': section,
      'r': reaction,
      'time': createdAt.toIso8601String(),
    };
  }
}

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

  /// خريطة التفاعلات المسجلة مع هذا التبليغ مفهرسة بمعرف الطالب
  Map<String, AnnouncementReaction> get reactions {
    final match = RegExp(r'\[REACTIONS:([^\]]+)\]').firstMatch(content);
    if (match != null) {
      try {
        final decoded = jsonDecode(match.group(1)!);
        if (decoded is Map) {
          final res = <String, AnnouncementReaction>{};
          decoded.forEach((key, val) {
            if (val is Map<String, dynamic>) {
              res[key.toString()] = AnnouncementReaction.fromJson(val);
            } else if (val is Map) {
              res[key.toString()] = AnnouncementReaction.fromJson(Map<String, dynamic>.from(val));
            }
          });
          return res;
        }
      } catch (_) {}
    }
    return const {};
  }

  /// قائمة كافة المتفاعلين (للمشرف العام حصراً)
  List<AnnouncementReaction> get reactionsList => reactions.values.toList();

  /// إجمالي عدد التفاعلات
  int get totalReactionsCount => reactions.length;

  /// إحصائية العدادات لكل إيموجي (تظهر لجميع الطلاب بهوية مجهولة)
  Map<String, int> get reactionCounts {
    final counts = <String, int>{};
    for (final r in reactions.values) {
      counts[r.reaction] = (counts[r.reaction] ?? 0) + 1;
    }
    return counts;
  }

  /// الإيموجي الذي تفاعل به مستخدم معين إن وجد
  String? getUserReaction(String? studentId) {
    if (studentId == null || studentId.isEmpty) return null;
    return reactions[studentId]?.reaction;
  }

  /// هل تفاعل الطالب بهذا الإيموجي تحديداً
  bool hasUserReacted(String? studentId, String emoji) {
    if (studentId == null || studentId.isEmpty) return false;
    return reactions[studentId]?.reaction == emoji;
  }

  /// تضمين أو تحديث وسم التفاعلات في نص المحتوى
  static String embedReactions(String originalContent, Map<String, AnnouncementReaction> newReactions) {
    final clean = originalContent.replaceAll(RegExp(r'\s*\[REACTIONS:[^\]]+\]'), '').trim();
    if (newReactions.isEmpty) return clean;
    final map = <String, dynamic>{};
    newReactions.forEach((k, v) => map[k] = v.toJson());
    final encoded = jsonEncode(map);
    return '$clean [REACTIONS:$encoded]';
  }

  /// إنشاء نسخة محدثة بتفاعلات جديدة
  AnnouncementModel copyWithReactions(Map<String, AnnouncementReaction> newReactions) {
    return AnnouncementModel(
      id: id,
      title: title,
      content: embedReactions(content, newReactions),
      authorId: authorId,
      authorName: authorName,
      authorRole: authorRole,
      department: department,
      stage: stage,
      section: section,
      category: category,
      isPinned: isPinned,
      imageUrl: imageUrl,
      subjectName: subjectName,
      createdAt: createdAt,
    );
  }

  /// المحتوى النظيف للعرض بدون وسوم تيليجرام والنظام الداخلية
  String get displayContent {
    return content
        .replaceAll(RegExp(r'\[TG_MSG_ID:\d+\]'), '')
        .replaceAll('[SCHEDULE_TIMETABLE]', '')
        .replaceAll(RegExp(r'\[COURSE_REGISTRY:[^\]]+\]'), '')
        .replaceAll(RegExp(r'\[SECTION:[^\]]+\]'), '')
        .replaceAll(RegExp(r'\[REACTIONS:[^\]]+\]'), '')
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

  Map<String, dynamic> toCacheJson() {
    return {
      'id': id,
      'title': title,
      'content': content,
      'author_id': authorId,
      'author_name': authorName,
      'author_role': authorRole,
      'department': department,
      'stage': stage,
      'section': section,
      'category': category,
      'is_pinned': isPinned,
      'image_url': imageUrl,
      'subject_name': subjectName,
      'created_at': createdAt.toIso8601String(),
    };
  }
}
