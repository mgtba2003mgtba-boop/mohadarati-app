import 'package:flutter_test/flutter_test.dart';
import 'package:nust_student_portal/models/app_user_model.dart';
import 'package:nust_student_portal/core/constants/app_constants.dart';

void main() {
  group('AppUserModel Multi-Section Access Control Tests', () {
    test('Single section student parses assignedSections correctly', () {
      final user = AppUserModel(
        id: '1',
        studentId: 'ST-001',
        name: 'علي أحمد',
        department: 'هندسة تقنيات الأجهزة الطبية',
        stage: 'المرحلة الثانية',
        section: 'A',
      );

      expect(user.assignedSections, equals(['A']));
      expect(user.hasMultipleSections, isFalse);
      expect(user.hasSectionAccess('A'), isTrue);
      expect(user.hasSectionAccess('a'), isTrue);
      expect(user.hasSectionAccess('B'), isFalse);
      expect(user.hasSectionAccess('ALL'), isTrue);
      expect(user.hasSectionAccess(null), isTrue);
      expect(user.sectionsDisplayLabel, equals('A'));
    });

    test('Multi-section representative with comma delimiters', () {
      final rep = AppUserModel(
        id: '2',
        studentId: 'ST-002',
        name: 'ممثل الدفعة',
        department: 'هندسة تقنيات الأجهزة الطبية',
        stage: 'المرحلة الثالثة',
        section: 'A, B',
        role: AppConstants.roleRepresentative,
      );

      expect(rep.assignedSections, containsAll(['A', 'B']));
      expect(rep.hasMultipleSections, isTrue);
      expect(rep.hasSectionAccess('A'), isTrue);
      expect(rep.hasSectionAccess('B'), isTrue);
      expect(rep.hasSectionAccess('C'), isFalse);
      expect(rep.hasSectionAccess('ALL'), isTrue);
      expect(rep.hasSectionAccess('الكل'), isTrue);
      expect(rep.hasSectionAccess('عام'), isTrue);
      expect(rep.sectionsDisplayLabel, equals('A، B'));
    });

    test('Multi-section with Arabic comma and slash delimiters', () {
      final repArabic = AppUserModel(
        id: '3',
        studentId: 'ST-003',
        name: 'ممثل شعبي',
        department: 'هندسة تقنيات الأجهزة الطبية',
        stage: 'المرحلة الأولى',
        section: 'A، B / C',
        role: AppConstants.roleRepresentative,
      );

      expect(repArabic.assignedSections, containsAll(['A', 'B', 'C']));
      expect(repArabic.hasMultipleSections, isTrue);
      expect(repArabic.hasSectionAccess('A'), isTrue);
      expect(repArabic.hasSectionAccess('B'), isTrue);
      expect(repArabic.hasSectionAccess('C'), isTrue);
      expect(repArabic.hasSectionAccess('D'), isFalse);
    });

    test('Admin always has full access to any section regardless of assignment', () {
      final admin = AppUserModel(
        id: '4',
        studentId: 'ST-ADMIN',
        name: 'المشرف العام',
        department: 'هندسة تقنيات الأجهزة الطبية',
        stage: 'المرحلة الأولى',
        section: 'A',
        role: AppConstants.roleAdmin,
      );

      expect(admin.hasSectionAccess('A'), isTrue);
      expect(admin.hasSectionAccess('B'), isTrue);
      expect(admin.hasSectionAccess('Z'), isTrue);
      expect(admin.hasSectionAccess('ANY_SECTION'), isTrue);
    });
  });
}
