import 'package:flutter_test/flutter_test.dart';
import 'package:nust_student_portal/models/grade_model.dart';

void main() {
  group('Dynamic Rubric & Student Grades Model Tests', () {
    test('SubjectGradeConfigModel parses custom columns and computes maxTotal', () {
      final configJson = {
        'id': 'SUB_MED_L2_S2_MIET2204',
        'subject_id': 'SUB_MED_L2_S2_MIET2204',
        'subject_name': 'أجهزة الكيمياء السريرية',
        'department': 'هندسة تقنيات الأجهزة الطبية',
        'stage': 'المرحلة الثانية',
        'section': 'ALL',
        'is_published': false,
        'columns': [
          {'id': 'c2', 'title': 'الشهر الثاني', 'maxScore': 15, 'order': 1},
          {'id': 'c1', 'title': 'الشهر الأول', 'maxScore': 15, 'order': 0},
          {'id': 'c3', 'title': 'العملي والكويزات', 'maxScore': 10, 'order': 2},
        ],
      };

      final config = SubjectGradeConfigModel.fromJson(configJson);
      expect(config.isPublished, isFalse);
      expect(config.columns.length, 3);
      expect(config.columns.first.title, 'الشهر الأول');
      expect(config.maxTotal, 40.0);
    });

    test('SubjectGradeViewData computes student total accurately when published', () {
      final config = SubjectGradeConfigModel.fromJson({
        'id': 'SUB_COMP_L2_S1_CET2102',
        'subject_id': 'SUB_COMP_L2_S1_CET2102',
        'subject_name': 'البرمجة الكيانية',
        'department': 'هندسة تقنيات الحاسوب',
        'stage': 'المرحلة الثانية',
        'is_published': true,
        'columns': [
          {'id': 'mid1', 'title': 'الشهر الأول', 'maxScore': 15, 'order': 0},
          {'id': 'mid2', 'title': 'الشهر الثاني', 'maxScore': 15, 'order': 1},
          {'id': 'lab', 'title': 'المختبر العملي', 'maxScore': 10, 'order': 2},
        ],
      });

      final studentGrade = StudentSubjectGradeModel.fromJson({
        'id': 'SUB_COMP_L2_S1_CET2102__ST-NUST-001',
        'subject_id': 'SUB_COMP_L2_S1_CET2102',
        'subject_name': 'البرمجة الكيانية',
        'student_id': 'ST-NUST-001',
        'student_name': 'علي حسن',
        'scores': {'mid1': 14, 'mid2': 13.5, 'lab': 9.5},
        'total_score': 37.0,
        'max_total': 40.0,
        'note': 'أداء ممتاز',
      });

      final viewData = SubjectGradeViewData(
        config: config,
        studentGrade: studentGrade,
      );

      expect(viewData.config.isPublished, isTrue);
      expect(viewData.hasAnyEnteredScore, isTrue);
      expect(viewData.earnedTotal, 37.0);
      expect(viewData.studentGrade?.note, 'أداء ممتاز');
    });
  });
}
