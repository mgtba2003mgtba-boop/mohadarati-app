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

/// نموذج صوت الطالب في الاستطلاع الأكاديمي
class PollVote {
  final String studentId;
  final String studentName;
  final String department;
  final String stage;
  final String section;
  final List<int> selectedOptionIndices;
  final DateTime votedAt;

  PollVote({
    required this.studentId,
    required this.studentName,
    this.department = '',
    this.stage = '',
    this.section = '',
    required this.selectedOptionIndices,
    required this.votedAt,
  });

  factory PollVote.fromJson(Map<String, dynamic> json) {
    DateTime time = DateTime.now();
    if (json['t'] != null) {
      try {
        time = DateTime.parse(json['t'].toString());
      } catch (_) {}
    }
    List<int> opts = [];
    if (json['o'] is List) {
      opts = (json['o'] as List).map((e) => int.tryParse(e.toString()) ?? 0).toList();
    } else if (json['o'] != null) {
      final single = int.tryParse(json['o'].toString());
      if (single != null) opts.add(single);
    }
    return PollVote(
      studentId: json['id']?.toString() ?? '',
      studentName: json['n']?.toString() ?? 'طالب',
      department: json['d']?.toString() ?? '',
      stage: json['st']?.toString() ?? '',
      section: json['s']?.toString() ?? '',
      selectedOptionIndices: opts,
      votedAt: time,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': studentId,
      'n': studentName,
      'd': department,
      'st': stage,
      's': section,
      'o': selectedOptionIndices,
      't': votedAt.toIso8601String(),
    };
  }
}

/// هيكل بيانات الاستطلاع الأكاديمي الشامل
class PollData {
  final String question;
  final List<String> options;
  final Map<String, PollVote> votes; // المفتاح هو studentId
  final bool isClosed;
  final bool allowsMultiple;

  PollData({
    required this.question,
    required this.options,
    this.votes = const {},
    this.isClosed = false,
    this.allowsMultiple = false,
  });

  int get totalVotersCount => votes.length;
  int get totalVotes => votes.length;
  String get embedTag => '[POLL:${jsonEncode(toJson())}]';

  int getVotesForOption(int optionIndex) {
    int count = 0;
    for (final v in votes.values) {
      if (v.selectedOptionIndices.contains(optionIndex)) {
        count++;
      }
    }
    return count;
  }

  int votesForOption(int optionIndex) => getVotesForOption(optionIndex);

  double getPercentageForOption(int optionIndex) {
    if (votes.isEmpty) return 0.0;
    final count = getVotesForOption(optionIndex);
    return (count / votes.length);
  }

  double percentageForOption(int optionIndex) {
    return getPercentageForOption(optionIndex) * 100;
  }

  PollData withVote(PollVote vote) {
    final updated = Map<String, PollVote>.from(votes);
    updated[vote.studentId] = vote;
    return copyWith(votes: updated);
  }

  bool hasStudentVoted(String? studentId) {
    if (studentId == null || studentId.isEmpty) return false;
    return votes.containsKey(studentId);
  }

  List<int> getStudentSelections(String? studentId) {
    if (studentId == null || studentId.isEmpty) return const [];
    return votes[studentId]?.selectedOptionIndices ?? const [];
  }

  List<PollVote> getVotersForOption(int optionIndex) {
    return votes.values.where((v) => v.selectedOptionIndices.contains(optionIndex)).toList();
  }

  factory PollData.fromJson(Map<String, dynamic> json) {
    final q = json['q']?.toString() ?? '';
    final opts = (json['opts'] as List?)?.map((e) => e.toString()).toList() ?? [];
    final isClosed = json['cls'] == true;
    final allowsMult = json['mult'] == true;
    final vMap = <String, PollVote>{};
    if (json['v'] is Map) {
      (json['v'] as Map).forEach((k, val) {
        if (val is Map<String, dynamic>) {
          vMap[k.toString()] = PollVote.fromJson(val);
        } else if (val is Map) {
          vMap[k.toString()] = PollVote.fromJson(Map<String, dynamic>.from(val));
        }
      });
    }
    return PollData(
      question: q,
      options: opts,
      votes: vMap,
      isClosed: isClosed,
      allowsMultiple: allowsMult,
    );
  }

  Map<String, dynamic> toJson() {
    final vJson = <String, dynamic>{};
    votes.forEach((k, v) => vJson[k] = v.toJson());
    return {
      'q': question,
      'opts': options,
      'cls': isClosed,
      'mult': allowsMultiple,
      'v': vJson,
    };
  }

  PollData copyWith({
    String? question,
    List<String>? options,
    Map<String, PollVote>? votes,
    bool? isClosed,
    bool? allowsMultiple,
  }) {
    return PollData(
      question: question ?? this.question,
      options: options ?? this.options,
      votes: votes ?? this.votes,
      isClosed: isClosed ?? this.isClosed,
      allowsMultiple: allowsMultiple ?? this.allowsMultiple,
    );
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

  /// هل هذا المنشور يمثل استطلاع رأي طلابي
  bool get isPoll => content.contains('[POLL:');

  /// استخراج نص JSON الصريح للاستطلاع مع معالجة الأقواس المعقوفة المتداخلة
  static String? extractPollJson(String text) {
    final startIndex = text.indexOf('[POLL:');
    if (startIndex == -1) return null;
    int depth = 0;
    int jsonStart = startIndex + 6;
    int jsonEnd = -1;
    for (int i = startIndex; i < text.length; i++) {
      if (text[i] == '[') {
        depth++;
      } else if (text[i] == ']') {
        depth--;
        if (depth == 0) {
          jsonEnd = i;
          break;
        }
      }
    }
    if (jsonEnd != -1 && jsonEnd > jsonStart) {
      return text.substring(jsonStart, jsonEnd);
    }
    return null;
  }

  /// إزالة وسم الاستطلاع بالكامل من النص
  static String stripPollTag(String text) {
    final startIndex = text.indexOf('[POLL:');
    if (startIndex == -1) return text;
    int depth = 0;
    int jsonEnd = -1;
    for (int i = startIndex; i < text.length; i++) {
      if (text[i] == '[') {
        depth++;
      } else if (text[i] == ']') {
        depth--;
        if (depth == 0) {
          jsonEnd = i;
          break;
        }
      }
    }
    if (jsonEnd != -1) {
      return (text.substring(0, startIndex) + text.substring(jsonEnd + 1)).trim();
    }
    return text;
  }

  /// استخراج بيانات الاستطلاع من المحتوى
  PollData? get pollData {
    final jsonStr = extractPollJson(content);
    if (jsonStr != null) {
      try {
        final decoded = jsonDecode(jsonStr);
        if (decoded is Map<String, dynamic>) {
          return PollData.fromJson(decoded);
        } else if (decoded is Map) {
          return PollData.fromJson(Map<String, dynamic>.from(decoded));
        }
      } catch (_) {}
    }
    return null;
  }

  /// تضمين أو تحديث وسم الاستطلاع في المحتوى
  static String embedPoll(String originalContent, PollData poll) {
    final clean = stripPollTag(originalContent);
    final encoded = jsonEncode(poll.toJson());
    return clean.isEmpty ? '[POLL:$encoded]' : '$clean [POLL:$encoded]';
  }

  /// إنشاء نسخة محدثة ببيانات استطلاع جديدة
  AnnouncementModel copyWithPoll(PollData newPoll) {
    return AnnouncementModel(
      id: id,
      title: title,
      content: embedPoll(content, newPoll),
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
    return stripPollTag(content)
        .replaceAll(RegExp(r'\[TG_MSG_ID:\d+\]'), '')
        .replaceAll('[SCHEDULE_TIMETABLE]', '')
        .replaceAll(RegExp(r'\[COURSE_REGISTRY:[^\]]+\]'), '')
        .replaceAll(RegExp(r'\[SECTION:[^\]]+\]'), '')
        .replaceAll(RegExp(r'\[REACTIONS:[^\]]+\]'), '')
        .replaceAll(RegExp(r'\[LECTURE_NOTE_V1\]\{[^{}]*\}'), '')
        .replaceAll(RegExp(r'\[LECTURE_NOTE_V1\]'), '')
        .replaceAll(RegExp(r'\[COURSE_OVERRIDE:[^\]]+\]'), '')
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

    String? derivedSubject = json['subject_name']?.toString();
    if (derivedSubject == null || derivedSubject.isEmpty) {
      if (rawContent.contains('[SCHEDULE_TIMETABLE]')) {
        derivedSubject = 'SCHEDULE';
      } else if (rawContent.contains('[HOME_BANNER]')) {
        derivedSubject = 'BANNER';
      } else if (rawContent.contains('[ANNOUNCEMENT]')) {
        derivedSubject = 'ANNOUNCEMENT';
      } else if (rawContent.contains('[COURSE')) {
        derivedSubject = 'COURSE';
      }
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
      subjectName: derivedSubject,
      createdAt: created,
    );
  }

  Map<String, dynamic> toJson() {
    String tagContent = content.trim();
    if (!tagContent.contains('[SECTION:')) {
      tagContent = '$tagContent [SECTION:$section]'.trim();
    }

    if (subjectName == 'ANNOUNCEMENT' && !tagContent.contains('[ANNOUNCEMENT]')) {
      tagContent = '$tagContent [ANNOUNCEMENT]'.trim();
    } else if (subjectName == 'BANNER' && !tagContent.contains('[HOME_BANNER]')) {
      tagContent = '$tagContent [HOME_BANNER]'.trim();
    } else if (subjectName == 'SCHEDULE' && !tagContent.contains('[SCHEDULE_TIMETABLE]')) {
      tagContent = '$tagContent [SCHEDULE_TIMETABLE]'.trim();
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

  /// حمولة قاعدة البيانات الصافية المستبعد منها الأعمدة غير المتوفرة في جدول announcements
  Map<String, dynamic> toDbJson() {
    final json = toJson();
    json.remove('subject_name');
    return json;
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
