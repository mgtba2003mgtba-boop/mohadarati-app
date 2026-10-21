import 'dart:convert';

class GradeColumnModel {
  final String id;
  final String title;
  final double maxScore;
  final int order;

  const GradeColumnModel({
    required this.id,
    required this.title,
    required this.maxScore,
    required this.order,
  });

  factory GradeColumnModel.fromJson(Map<String, dynamic> json) {
    return GradeColumnModel(
      id: (json['id'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      maxScore: double.tryParse((json['maxScore'] ?? json['max_score'] ?? 0).toString()) ?? 0.0,
      order: int.tryParse((json['order'] ?? 0).toString()) ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'maxScore': maxScore,
        'order': order,
      };
}

class SubjectGradeConfigModel {
  final String id;
  final String subjectId;
  final String subjectName;
  final String department;
  final String stage;
  final String section;
  final bool isPublished;
  final List<GradeColumnModel> columns;

  const SubjectGradeConfigModel({
    required this.id,
    required this.subjectId,
    required this.subjectName,
    required this.department,
    required this.stage,
    this.section = 'ALL',
    required this.isPublished,
    required this.columns,
  });

  double get maxTotal => columns.fold(0.0, (sum, c) => sum + c.maxScore);

  factory SubjectGradeConfigModel.fromJson(Map<String, dynamic> json) {
    List<GradeColumnModel> parsedColumns = [];
    final rawCols = json['columns'];
    if (rawCols is List) {
      parsedColumns = rawCols
          .whereType<Map>()
          .map((e) => GradeColumnModel.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } else if (rawCols is String && rawCols.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(rawCols);
        if (decoded is List) {
          parsedColumns = decoded
              .whereType<Map>()
              .map((e) => GradeColumnModel.fromJson(Map<String, dynamic>.from(e)))
              .toList();
        }
      } catch (_) {}
    }
    parsedColumns.sort((a, b) => a.order.compareTo(b.order));

    return SubjectGradeConfigModel(
      id: (json['id'] ?? json['subject_id'] ?? '').toString(),
      subjectId: (json['subject_id'] ?? json['subjectId'] ?? json['id'] ?? '').toString(),
      subjectName: (json['subject_name'] ?? json['subjectName'] ?? '').toString(),
      department: (json['department'] ?? '').toString(),
      stage: (json['stage'] ?? '').toString(),
      section: (json['section'] ?? 'ALL').toString(),
      isPublished: json['is_published'] == true || json['isPublished'] == true,
      columns: parsedColumns,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'subject_id': subjectId,
        'subject_name': subjectName,
        'department': department,
        'stage': stage,
        'section': section,
        'is_published': isPublished,
        'columns': columns.map((c) => c.toJson()).toList(),
      };
}

class StudentSubjectGradeModel {
  final String id;
  final String subjectId;
  final String subjectName;
  final String studentId;
  final String studentName;
  final Map<String, double> scores;
  final double totalScore;
  final double maxTotal;
  final String note;
  final DateTime? updatedAt;

  const StudentSubjectGradeModel({
    required this.id,
    required this.subjectId,
    required this.subjectName,
    required this.studentId,
    required this.studentName,
    required this.scores,
    required this.totalScore,
    required this.maxTotal,
    this.note = '',
    this.updatedAt,
  });

  factory StudentSubjectGradeModel.fromJson(Map<String, dynamic> json) {
    final Map<String, double> parsedScores = {};
    final rawScores = json['scores'];
    if (rawScores is Map) {
      rawScores.forEach((k, v) {
        final d = double.tryParse(v.toString());
        if (d != null) parsedScores[k.toString()] = d;
      });
    } else if (rawScores is String && rawScores.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(rawScores);
        if (decoded is Map) {
          decoded.forEach((k, v) {
            final d = double.tryParse(v.toString());
            if (d != null) parsedScores[k.toString()] = d;
          });
        }
      } catch (_) {}
    }

    return StudentSubjectGradeModel(
      id: (json['id'] ?? '').toString(),
      subjectId: (json['subject_id'] ?? json['subjectId'] ?? '').toString(),
      subjectName: (json['subject_name'] ?? json['subjectName'] ?? '').toString(),
      studentId: (json['student_id'] ?? json['studentId'] ?? '').toString(),
      studentName: (json['student_name'] ?? json['studentName'] ?? '').toString(),
      scores: parsedScores,
      totalScore: double.tryParse((json['total_score'] ?? json['totalScore'] ?? 0).toString()) ?? 0.0,
      maxTotal: double.tryParse((json['max_total'] ?? json['maxTotal'] ?? 0).toString()) ?? 0.0,
      note: (json['note'] ?? '').toString(),
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'].toString())
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'subject_id': subjectId,
        'subject_name': subjectName,
        'student_id': studentId,
        'student_name': studentName,
        'scores': scores,
        'total_score': totalScore,
        'max_total': maxTotal,
        'note': note,
        'updated_at': updatedAt?.toIso8601String(),
      };
}

class SubjectGradeViewData {
  final SubjectGradeConfigModel config;
  final StudentSubjectGradeModel? studentGrade;

  const SubjectGradeViewData({
    required this.config,
    this.studentGrade,
  });

  double get earnedTotal {
    if (studentGrade == null) return 0.0;
    double sum = 0.0;
    for (final col in config.columns) {
      final s = studentGrade!.scores[col.id];
      if (s != null) sum += s;
    }
    return sum;
  }

  bool get hasAnyEnteredScore {
    if (studentGrade == null) return false;
    return studentGrade!.scores.isNotEmpty || studentGrade!.note.trim().isNotEmpty;
  }
}
