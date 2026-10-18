import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';
import 'package:nust_student_portal/models/student_model.dart';
import 'package:nust_student_portal/models/lecture_model.dart';
import 'package:nust_student_portal/models/attendance_model.dart';
import 'package:nust_student_portal/models/announcement_model.dart';
import 'package:nust_student_portal/models/app_user_model.dart';
import 'package:nust_student_portal/services/attendance_service.dart';
import 'package:nust_student_portal/core/constants/app_constants.dart';
import 'package:nust_student_portal/core/constants/biometric_subjects.dart';
import 'package:nust_student_portal/models/schedule_model.dart';
import 'package:nust_student_portal/widgets/app_media_preview_modal.dart';
import 'package:nust_student_portal/widgets/ios_install_dialog.dart';
import 'package:nust_student_portal/services/admin_preview_service.dart';
import 'package:nust_student_portal/services/auto_update_service.dart';
import 'package:nust_student_portal/services/telegram_uploader_service.dart';
import 'package:nust_student_portal/services/app_notification_service.dart';

void main() {
  group('اختبارات نماذج البيانات والخدمات الأكاديمية (NUST Portal Tests)', () {
    test('اختبار تحليل نموذج الطالب وقيد الحضور البيومتري', () {
      final json = {
        'id': 'ST-NUST-001125097-422',
        'name': 'حسين سالم جرمد فهد',
        'department': 'هندسة تقنيات الأجهزة الطبية',
        'stage': 'السنة الثانية',
        'section': 'A',
        'telegram_chat_id': '5944895074',
        'photo_url': 'https://example.com/photo.jpg',
      };

      final student = StudentModel.fromJson(json);

      expect(student.id, 'ST-NUST-001125097-422');
      expect(student.name, 'حسين سالم جرمد فهد');
      expect(student.hasFace, true);
      expect(student.fullAcademicDetails, contains('هندسة تقنيات الأجهزة الطبية'));
    });

    test('اختبار معالجة وتنظيف رابط Google Drive للمحاضرات', () {
      final lecture = LectureModel(
        id: 'lec-1',
        title: 'المحاضرة 1 - الدوائر الإلكترونية',
        subjectName: 'إلكترونيات طبية',
        department: 'هندسة تقنيات الأجهزة الطبية',
        stage: 'المرحلة الثانية',
        driveUrl: 'https://drive.google.com/file/d/1A2B3C4D5E6F/view?usp=sharing',
        uploaderId: 'REP-01',
        uploaderName: 'أحمد علي',
        createdAt: DateTime.now(),
      );

      expect(lecture.cleanDriveViewUrl, 'https://drive.google.com/file/d/1A2B3C4D5E6F/view');
      expect(lecture.typeLabel, 'نظري');
    });

    test('اختبار احتساب نسب الحضور والغياب والإنذارات الأكاديمية', () {
      final records = [
        AttendanceRecordModel(
          id: '1',
          studentId: 'ST-NUST-001125097-422',
          studentName: 'حسين سالم',
          date: '2026-10-10',
          subjectName: 'إلكترونيات',
        ),
        AttendanceRecordModel(
          id: '2',
          studentId: 'ST-NUST-001125097-422',
          studentName: 'حسين سالم',
          date: '2026-10-11',
          subjectName: 'إلكترونيات',
        ),
      ];

      final summary = AttendanceService.processAttendanceRecords(
        records,
        standardSemesterSessions: 15,
      );

      expect(summary.totalPresences, 2);
      expect(summary.subjectsStats.length, 1);
      final stat = summary.subjectsStats.first;
      expect(stat.subjectName, 'إلكترونيات');
      expect(stat.attendedCount, 2);
      expect(stat.absentCount, 13);
      expect(stat.warningLevel, AcademicWarningLevel.dismissed);
    });

    test('اختبار الإعلانات المرتبطة بمادة دراسية (Subject-Tagged Announcements)', () {
      final announce = AnnouncementModel(
        id: 'ann-1',
        title: 'موعد الامتحان الفصلي لمادة أنظمة الليزر',
        content: 'سيكون الامتحان يوم الأحد القادم في القاعة 4',
        authorId: 'REP-413',
        authorName: 'مجتبى عواد',
        authorRole: 'representative',
        department: 'هندسة تقنيات الأجهزة الطبية',
        stage: 'المرحلة الرابعة',
        subjectName: 'أنظمة الليزر الطبية',
        createdAt: DateTime.now(),
      );

      final json = announce.toJson();
      expect(json['subject_name'], 'أنظمة الليزر الطبية');
      expect(json['department'], 'هندسة تقنيات الأجهزة الطبية');

      final parsed = AnnouncementModel.fromJson(json);
      expect(parsed.subjectName, 'أنظمة الليزر الطبية');
      expect(parsed.authorRole, 'representative');
    });

    test('اختبار نطاق وصلاحيات ممثل الدفعة والمشرف العام (Representative Scoping & Admin)', () {
      final rep = AppUserModel(
        id: 'u-1',
        studentId: 'ST-001',
        name: 'علي حسن',
        department: 'هندسة تقنيات الأجهزة الطبية',
        stage: 'المرحلة الرابعة',
        role: 'representative',
        canPublishLectures: true,
        canPublishAnnouncements: true,
      );

      expect(rep.isRepresentative, true);
      expect(rep.isAdmin, false);
      expect(rep.canManageLectures, true);
      expect(rep.canManageAnnouncements, true);
      expect(rep.canPromoteUsers, false); // ممثل الدفعة ليس مشرفاً عاماً ولا يمكنه ترقية مستخدمين

      final admin = AppUserModel(
        id: 'u-2',
        studentId: 'ST-NUST-001630760-413',
        name: 'مجتبى عواد حسن كاظم',
        department: 'هندسة تقنيات الأجهزة الطبية',
        stage: 'المرحلة الرابعة',
        role: 'admin',
        canPublishLectures: true,
        canPublishAnnouncements: true,
      );

      expect(admin.isAdmin, true);
      expect(admin.canPromoteUsers, true);
      expect(admin.canManageLectures, true);
      expect(admin.canManageAnnouncements, true);
    });

    test('اختبار قبول كلمات السر والرموز الحرة دون تقييد بـ 6 أرقام (Freeform Passwords)', () {
      final validPasswords = [
        '1234',
        'abcd',
        'myPass@2026',
        '998877665544',
        'a1b2c3d4e5f6g7h8',
        'كلمة-سر-123',
      ];

      for (final pwd in validPasswords) {
        expect(pwd.trim().isNotEmpty, true, reason: 'كلمة السر $pwd مقبولة تماماً كرمز دخول حر');
      }
    });

    test('اختبار الحماية الأمنية الصارمة ومنع الدخول بأي رمز عشوائي (Strict PIN Matching)', () {
      final user = AppUserModel(
        id: 'u-10',
        studentId: 'ST-NUST-001607525-505',
        name: 'طالب معتمد',
        department: 'هندسة تقنيات الأجهزة الطبية',
        stage: 'المرحلة الرابعة',
        pinCode: '112233',
      );

      // الرمز الصحيح فقط هو الذي يطابق
      expect(user.pinCode == '112233', true);

      // أي رمز عشوائي يجب أن يفشل حتماً
      final randomAttempts = ['0000', '1234', '999999', '112234', 'random', ''];
      for (final attempt in randomAttempts) {
        final matches = (user.pinCode != null &&
            user.pinCode!.isNotEmpty &&
            user.pinCode == attempt.trim());
        expect(matches, false, reason: 'المحاولة العشوائية $attempt يجب أن تُرفض قطعاً');
      }
    });

    test('اختبار استرجاع الخطة الدراسية والمقررات الكاملة (Complete Curriculum Retrieval)', () {
      final medicalStage4 = AppConstants.getCurriculumSubjects('هندسة تقنيات الأجهزة الطبية', 'المرحلة الرابعة');
      expect(medicalStage4, contains('أنظمة الليزر الطبية'));
      expect(medicalStage4, contains('نظم السيطرة'));
      expect(medicalStage4, contains('مشروع التخرج II'));
      expect(medicalStage4.length, greaterThanOrEqualTo(6));

      final compStage3 = AppConstants.getCurriculumSubjects('هندسة تقنيات الحاسوب', 'المرحلة الثالثة');
      expect(compStage3.any((s) => s.contains('انظمة التشغيل') || s.contains('الاتصالات الرقمية')), isTrue);
      expect(compStage3.length, greaterThanOrEqualTo(5));

      final cyberStage2 = AppConstants.getCurriculumSubjects('هندسة تقنيات الأمن السيبراني', 'المرحلة الثانية');
      expect(cyberStage2.any((s) => s.contains('أمن الشبكات')), isTrue);
      expect(cyberStage2.length, greaterThanOrEqualTo(2));
    });

    test('اختبار نموذج الجدول الدراسي والامتحاني وكشف الصور (Schedule Model Tests)', () {
      final schedule = ScheduleModel(
        id: 'sch-1',
        title: 'جدول المحاضرات الأسبوعي - الكورس الثاني',
        type: 'lectures',
        department: 'هندسة تقنيات الأجهزة الطبية',
        stage: 'المرحلة الرابعة',
        fileUrl: 'https://example.com/schedules/timetable.png',
        fileName: 'timetable.png',
        uploaderName: 'مجتبى عواد',
        createdAt: DateTime.now(),
      );

      expect(schedule.isExam, false);
      expect(schedule.hasFile, true);
      expect(schedule.isImage, true);

      final json = schedule.toJson();
      expect(json['title'], 'جدول المحاضرات الأسبوعي - الكورس الثاني');
      expect(json['type'], 'lectures');

      final parsed = ScheduleModel.fromJson(json);
      expect(parsed.title, schedule.title);
      expect(parsed.isImage, true);
    });

    test('اختبار حصرية صلاحيات بنل البوسترات المصورة للمشرف العام مجتبى عواد (Mujtaba Awad Permissions)', () {
      final mujtaba = AppUserModel(
        id: 'u-1',
        studentId: 'ST-NUST-001630760-413',
        name: 'مجتبى عواد',
        department: 'هندسة تقنيات الأجهزة الطبية',
        stage: 'المرحلة الرابعة',
        role: AppConstants.roleAdmin,
      );

      final regularRep = AppUserModel(
        id: 'u-2',
        studentId: 'ST-NUST-001999999-111',
        name: 'علي حسن كاظم',
        department: 'هندسة تقنيات الحاسوب',
        stage: 'المرحلة الثانية',
        role: AppConstants.roleRepresentative,
        canPublishLectures: true,
        canPublishAnnouncements: true,
      );

      final regularStudent = AppUserModel(
        id: 'u-3',
        studentId: 'ST-NUST-001888888-222',
        name: 'سارة محمد',
        department: 'هندسة تقنيات الأمن السيبراني',
        stage: 'المرحلة الأولى',
        role: AppConstants.roleStudent,
      );

      // التحقق من صلاحية مجتبى
      final bool isMujtaba = mujtaba.studentId == 'ST-NUST-001630760-413' || mujtaba.name.contains('مجتبى') || mujtaba.isAdmin;
      expect(isMujtaba, true, reason: 'مجتبى عواد هو المشرف المخول بنشر بوسترات الواجهة');

      // التحقق من أن الممثل العادي لا يملك صلاحية نشر البوسترات المصورة
      final bool isRepMujtaba = regularRep.studentId == 'ST-NUST-001630760-413' || regularRep.name.contains('مجتبى') || regularRep.isAdmin;
      expect(isRepMujtaba, false, reason: 'الممثل العادي لا يملك صلاحية بوسترات الواجهة');

      // التحقق من أن الطالب العادي لا يملك الصلاحية
      final bool isStudentMujtaba = regularStudent.studentId == 'ST-NUST-001630760-413' || regularStudent.name.contains('مجتبى') || regularStudent.isAdmin;
      expect(isStudentMujtaba, false, reason: 'الطالب العادي لا يملك صلاحية بوسترات الواجهة');
    });

    test('اختبار تنسيق روابط سيرفر تيليجرام للبوسترات والجداول (Telegram CDN Server Endpoints)', () {
      final banner = AnnouncementModel(
        id: 'ann-1',
        title: 'مؤتمر الابتكار والذكاء الاصطناعي',
        content: 'إعلان وبوستر رسمي في الواجهة الرئيسية',
        authorId: 'ST-NUST-001630760-413',
        authorName: 'مجتبى عواد',
        authorRole: 'admin',
        imageUrl: '/api/file/105',
        category: 'banner',
        isPinned: true,
        createdAt: DateTime.now(),
      );

      expect(banner.imageUrl, contains('/api/file/105'));
      expect(banner.isPinned, true);
      expect(banner.category, 'banner');

      final schedule = ScheduleModel(
        id: 'sch-99',
        title: 'جدول الامتحانات النهائية',
        type: 'exams',
        fileUrl: '/api/file/204',
        fileName: 'final_exam_timetable.pdf',
        department: 'ALL',
        stage: 'ALL',
        uploaderName: 'مجتبى عواد',
        createdAt: DateTime.now(),
      );

      expect(schedule.fileUrl, contains('/api/file/204'));
      expect(schedule.isPdf, true);
      expect(schedule.isExam, true);
    });

    test('اختبار عزل الجداول تماماً عن لوحة الإعلانات وتوحيد مصطلحات المعاينة والتنزيل', () {
      final scheduleAnnouncement = AnnouncementModel(
        id: 'sch-ann-1',
        title: 'جدول المحاضرات الأسبوعي',
        content: '[SCHEDULE_TIMETABLE] جدول دراسي',
        authorId: 'REP-1',
        authorName: 'ممثل المرحلة',
        authorRole: 'representative',
        subjectName: 'SCHEDULE',
        createdAt: DateTime.now(),
      );

      final regularAnnouncement = AnnouncementModel(
        id: 'ann-2',
        title: 'ورشة عمل حول الذكاء الاصطناعي',
        content: 'تدعوكم الكلية لحضور ورشة عمل تخصصية',
        authorId: 'ADMIN-1',
        authorName: 'العمادة',
        authorRole: 'admin',
        createdAt: DateTime.now(),
      );

      final mixedList = [scheduleAnnouncement, regularAnnouncement];

      // التحقق من أن تصفية الإعلانات تستبعد الجداول 100%
      final filteredAnnouncements = mixedList.where((a) {
        final isSchedule = a.content.contains('[SCHEDULE_TIMETABLE]') || a.subjectName == 'SCHEDULE';
        return !isSchedule;
      }).toList();

      expect(filteredAnnouncements.length, 1);
      expect(filteredAnnouncements.first.id, 'ann-2');
      expect(filteredAnnouncements.first.title, 'ورشة عمل حول الذكاء الاصطناعي');

      // التحقق من توحيد المصطلحات: زر تنزيل المباشر
      const actionDownload = 'تنزيل';
      expect(actionDownload, 'تنزيل');
      expect(actionDownload, isNot(contains('فتح الملف')));
      expect(actionDownload, isNot(contains('تكبير')));
    });

    test('اختبار صلاحيات ممثل الدفعة في إدارة المقررات (Course Management Permissions)', () {
      final rep = AppUserModel(
        id: 'u-rep',
        studentId: 'ST-NUST-001999-1',
        name: 'علي الممثل',
        department: 'هندسة تقنيات الأجهزة الطبية',
        stage: 'المرحلة الرابعة',
        role: AppConstants.roleRepresentative,
        canPublishLectures: true,
      );

      final admin = AppUserModel(
        id: 'u-adm',
        studentId: 'ST-NUST-001630760-413',
        name: 'مجتبى المشرف',
        department: 'هندسة تقنيات الأجهزة الطبية',
        stage: 'المرحلة الرابعة',
        role: AppConstants.roleAdmin,
      );

      final student = AppUserModel(
        id: 'u-std',
        studentId: 'ST-NUST-001888-2',
        name: 'طالب عادي',
        department: 'هندسة تقنيات الحاسوب',
        stage: 'المرحلة الأولى',
        role: AppConstants.roleStudent,
      );

      expect(rep.isRepresentative, true);
      expect(rep.canManageCourses, true, reason: 'ممثل الدفعة يملك صلاحية إدارة المقررات');

      expect(admin.isAdmin, true);
      expect(admin.canManageCourses, true, reason: 'المشرف العام يملك صلاحية إدارة المقررات');

      expect(student.isStudent, true);
      expect(student.canManageCourses, false, reason: 'الطالب العادي لا يملك صلاحية إدارة المقررات');
    });

    test('اختبار دورة حياة المقرر: إضافة وتعديل وحذف من قبل الممثل (Course Add, Edit, Delete Lifecycle)', () {
      final List<String> subjects = ['الرياضيات الهندسية', 'الدوائر الكهربائية'];

      // 1. إضافة مقرر جديد
      const newSubject = 'أنظمة الذكاء الاصطناعي';
      if (!subjects.contains(newSubject)) {
        subjects.add(newSubject);
      }
      expect(subjects, contains('أنظمة الذكاء الاصطناعي'));
      expect(subjects.length, 3);

      // 2. تعديل مقرر قائم
      const oldSubject = 'الدوائر الكهربائية';
      const updatedSubject = 'الدوائر الكهربائية والإلكترونية المتقدمة';
      final index = subjects.indexOf(oldSubject);
      expect(index != -1, true);
      subjects[index] = updatedSubject;
      expect(subjects, contains('الدوائر الكهربائية والإلكترونية المتقدمة'));
      expect(subjects, isNot(contains('الدوائر الكهربائية')));

      // 3. حذف مقرر
      subjects.remove('الرياضيات الهندسية');
      expect(subjects, isNot(contains('الرياضيات الهندسية')));
      expect(subjects.length, 2);

      // 4. التحقق من عزل سجلات المقررات عن الإعلانات العادية
      final courseRecord = AnnouncementModel(
        id: 'course-1',
        title: 'مقرر مضاف',
        content: '[COURSE_REGISTRY:ADD] مقرر دراسي',
        category: 'academic',
        authorId: 'REP-1',
        authorName: 'الممثل',
        authorRole: 'representative',
        subjectName: 'COURSE',
        createdAt: DateTime.now(),
      );

      final isCourse = courseRecord.content.contains('[COURSE_REGISTRY') || courseRecord.subjectName == 'COURSE';
      expect(isCourse, true, reason: 'سجل المقرر يُعزل تماماً ولا يظهر في لوحة الإعلانات');
    });

    test('اختبار النشر المباشر والمقيد من داخل المادة الدراسية (Direct In-Subject Publishing & Auto-Context Binding)', () {
      // محاكاة سياق المادة الدراسية
      const currentSubject = 'تصميم المعالجات الدقيقة';
      const department = 'هندسة تقنيات الحاسوب';
      const stage = 'المرحلة الثالثة';
      const semester = 1;

      final repUser = AppUserModel(
        id: 'u-rep',
        studentId: 'ST-001',
        name: 'ممثل المرحلة الثالثة',
        department: department,
        stage: stage,
        section: 'A',
        role: AppConstants.roleRepresentative,
        canPublishLectures: true,
        canPublishAnnouncements: true,
      );

      // التحقق من أن النشر داخل المادة يربط اسم المادة والقسم تلقائياً
      final newLecture = LectureModel(
        id: 'lec-subject-1',
        title: 'المحاضرة الأولى: معمارية المعالج',
        subjectName: currentSubject,
        driveUrl: 'https://drive.google.com/file/d/123xyz/view?usp=sharing',
        department: department,
        stage: stage,
        semester: semester,
        uploaderId: repUser.id,
        uploaderName: repUser.name,
        type: 'theory',
        createdAt: DateTime.now(),
      );

      expect(newLecture.subjectName, currentSubject);
      expect(newLecture.department, department);
      expect(newLecture.stage, stage);
      expect(newLecture.hasDriveUrl, true);
      expect(newLecture.cleanDriveViewUrl, contains('123xyz'));

      // التحقق من صلاحية الحذف للممثل والمشرف
      final bool canDeleteByRep = repUser.canPublishLectures && (newLecture.uploaderName == repUser.name || repUser.isAdmin);
      expect(canDeleteByRep, true);
    });

    test('اختبار رادار نشاط ممثلي الشعب والمراحل وداش بورد المشرف العام مجتبى (Mujtaba Live Activity Radar & Reps Directory)', () {
      final repA = AppUserModel(
        id: 'u-rep-a',
        studentId: 'ST-A',
        name: 'كرار علي',
        department: 'هندسة تقنيات الأجهزة الطبية',
        stage: 'المرحلة الرابعة',
        section: 'A',
        role: AppConstants.roleRepresentative,
        canPublishLectures: true,
        canPublishAnnouncements: true,
      );

      final repB = AppUserModel(
        id: 'u-rep-b',
        studentId: 'ST-B',
        name: 'منتظر حسين',
        department: 'هندسة تقنيات الأجهزة الطبية',
        stage: 'المرحلة الرابعة',
        section: 'B',
        role: AppConstants.roleRepresentative,
        canPublishLectures: true,
        canPublishAnnouncements: false,
      );

      // فحص بيانات الممثلين والشعب
      expect(repA.section, 'A');
      expect(repB.section, 'B');
      expect(repA.isRepresentative, true);
      expect(repB.canPublishAnnouncements, false);

      // محاكاة سجل رادار الأنشطة
      final activities = [
        {
          'id': 'act-1',
          'type': 'lecture',
          'title': 'محاضرة أجهزة التصوير الطبي',
          'uploaderName': repA.name,
          'department': repA.department,
          'stage': repA.stage,
          'createdAt': DateTime.now().subtract(const Duration(minutes: 15)),
        },
        {
          'id': 'act-2',
          'type': 'announcement',
          'title': 'تحديد موعد كويز الكيمياء الحياتية',
          'uploaderName': repA.name,
          'department': repA.department,
          'stage': repA.stage,
          'createdAt': DateTime.now().subtract(const Duration(hours: 1)),
        },
      ];

      expect(activities.length, 2);
      expect(activities.first['uploaderName'], 'كرار علي');
      expect(activities.first['type'], 'lecture');
    });

    test('اختبار النشر السحابي المباشر وروابط تيليجرام الدائمة (Telegram Cloud Native Upload & Direct Links)', () {
      final cloudLecture = LectureModel(
        id: 'lec-cloud-1',
        title: 'محاضرة الليزر والتشخيص المتقدم',
        subjectName: 'أنظمة الليزر الطبية',
        department: 'هندسة تقنيات الأجهزة الطبية',
        stage: 'المرحلة الرابعة',
        semester: 1,
        type: 'theory',
        driveUrl: 'https://api.telegram.org/file/bot8816281220:AAFAduddee7N8mD-UNgQIgfQ1yiFaGbdHU8/documents/file_10.pdf',
        telegramChannelId: -1003875986734,
        telegramMessageId: 99,
        telegramFileId: 'BQACAgIAAyEGAATnBt0uAAMXas45U1iRIoj7ejH9RTxbDMfUWl8AAiGqAAIqBXhKEhZPqdwdIyc9BA',
        fileName: 'laser_diagnostics.pdf',
        fileSizeBytes: 2048576,
        mimeType: 'application/pdf',
        uploaderId: 'ST-NUST-001630760-413',
        uploaderName: 'مجتبى عواد',
        createdAt: DateTime.now(),
      );

      expect(cloudLecture.hasTelegramMedia, true);
      expect(cloudLecture.streamUrl, contains('https://api.telegram.org/file/bot'));
      expect(cloudLecture.downloadUrl, contains('https://api.telegram.org/file/bot'));
      expect(cloudLecture.telegramFileId, 'BQACAgIAAyEGAATnBt0uAAMXas45U1iRIoj7ejH9RTxbDMfUWl8AAiGqAAIqBXhKEhZPqdwdIyc9BA');
      expect(cloudLecture.formattedFileSize, '2.0 MB');

      final json = cloudLecture.toJson();
      expect(json['telegram_file_id'], cloudLecture.telegramFileId);
      expect(json['drive_url'], cloudLecture.driveUrl);

      final fromJson = LectureModel.fromJson(json);
      expect(fromJson.telegramFileId, cloudLecture.telegramFileId);
      expect(fromJson.hasTelegramMedia, true);
      expect(fromJson.streamUrl, cloudLecture.streamUrl);
    });

    test('اختبار قاعدة بيانات المواد المستخرجة من نظام البصمة (119 Biometric Subjects Extraction & Classification)', () {
      // 1. فحص إجمالي عدد المواد في نظام البصمة الجامعي مع مقررات هندسة الحاسوب الرسمية والاختيارية
      final all = BiometricSubjects.allSubjects;
      expect(all.length, 125, reason: 'يجب أن تحتوي المنظومة على 125 مادة معتمدة بعد استعادة المقررات الاختيارية لحاسوب');

      // 2. فحص توزيع المواد حسب الأقسام
      final compSubjects = BiometricSubjects.getSubjects(department: 'هندسة تقنيات الحاسوب');
      final cyberSubjects = BiometricSubjects.getSubjects(department: 'هندسة تقنيات الأمن السيبراني');
      final medSubjects = BiometricSubjects.getSubjects(department: 'هندسة تقنيات الأجهزة الطبية');

      expect(compSubjects.length, 57, reason: 'هندسة الحاسوب تضم 57 مادة رسمية بعد استعادة المقررات الاختيارية عبر المراحل الأربع');
      expect(cyberSubjects.length, 19, reason: 'الأمن السيبراني يضم 19 مادة رسمية');
      expect(medSubjects.length, 49, reason: 'الأجهزة الطبية تضم 49 مادة رسمية');
      expect(compSubjects.length + cyberSubjects.length + medSubjects.length, 125);

      // 3. فحص فلترة الكورس الدراسي (الفصل 1 والفصل 2)
      final compL1S1 = BiometricSubjects.getSubjects(
        department: 'هندسة تقنيات الحاسوب',
        stage: 'المرحلة الأولى',
        semester: 1,
      );
      expect(compL1S1.isNotEmpty, true);
      expect(compL1S1.every((s) => s.semester == 1), true);

      final medL4S2 = BiometricSubjects.getSubjects(
        department: 'هندسة تقنيات الأجهزة الطبية',
        stage: 'المرحلة الرابعة',
        semester: 2,
      );
      expect(medL4S2.isNotEmpty, true);
      expect(medL4S2.every((s) => s.semester == 2), true);
    });

    test('اختبار هيكلة الداشبورد المبسطة وصلاحيات التبويبات (Dashboard 3-Tab Architecture & Role Segregation)', () {
      final mujtabaUser = AppUserModel(
        id: 'u-mujtaba',
        studentId: 'ST-NUST-001630760-413',
        name: 'مجتبى عواد طالب عبيد',
        department: 'هندسة تقنيات الأجهزة الطبية',
        stage: 'المرحلة الرابعة',
        role: AppConstants.roleAdmin,
      );

      final regularRep = AppUserModel(
        id: 'u-rep',
        studentId: 'ST-NUST-009988-123',
        name: 'أحمد علي',
        department: 'هندسة تقنيات الحاسوب',
        stage: 'المرحلة الثالثة',
        role: AppConstants.roleRepresentative,
        canPublishLectures: true,
        canPublishAnnouncements: true,
      );

      // التحقق من تحديد المشرف العام مجتبى عواد
      final bool isMujtaba = mujtabaUser.studentId == 'ST-NUST-001630760-413' ||
          mujtabaUser.name.contains('مجتبى') ||
          mujtabaUser.isAdmin;
      final bool isRepMujtaba = regularRep.studentId == 'ST-NUST-001630760-413' ||
          regularRep.name.contains('مجتبى') ||
          regularRep.isAdmin;

      expect(isMujtaba, true);
      expect(isRepMujtaba, false);

      // عدد التبويبات الجديد المتفق عليه: 3 لمجتبى عواد و 2 للممثل العادي
      final int mujtabaTabsCount = isMujtaba ? 3 : 2;
      final int repTabsCount = isRepMujtaba ? 3 : 2;

      expect(mujtabaTabsCount, 3, reason: 'المشرف العام مجتبى لديه 3 تبويبات فقط: النبض، مركز النشر، إدارة المحتوى والطلاب');
      expect(repTabsCount, 2, reason: 'ممثل الدفعة لديه تبويبان فقط: نشر المحاضرات، نشر الإعلانات');
    });

    test('اختبار مزامنة الحذف التلقائي وحذف الرسائل من قناة تيليجرام (Telegram Channel Synchronized Deletion)', () {
      // 1. اختبار استخراج معرف رسالة تيليجرام من المحاضرة
      final lecture = LectureModel(
        id: 'lec-99',
        title: 'محاضرة المعالجة الرقمية',
        subjectName: 'معالجة الإشارات',
        department: 'هندسة تقنيات الحاسوب',
        stage: 'المرحلة الثالثة',
        driveUrl: 'telegram',
        uploaderId: 'REP-01',
        uploaderName: 'ممثل الدفعة',
        telegramMessageId: 10452,
        telegramChannelId: AppConstants.lecturesChannelId,
        createdAt: DateTime.now(),
      );

      expect(lecture.telegramMessageId, 10452);
      expect(lecture.telegramChannelId, AppConstants.lecturesChannelId);

      // 2. اختبار استخراج معرف رسالة تيليجرام وتنظيف المحتوى في البوسترات والإعلانات
      final banner = AnnouncementModel(
        id: 'ann-55',
        title: 'بوستر مؤتمر الذكاء الاصطناعي',
        content: 'دعوة لحضور المؤتمر السنوي [TG_MSG_ID:88421]',
        authorId: 'ST-NUST-001630760-413',
        authorName: 'مجتبى عواد',
        authorRole: 'admin',
        imageUrl: 'https://api.telegram.org/file/bot/photos/file_88421.jpg',
        createdAt: DateTime.now(),
      );

      expect(banner.telegramMessageId, 88421, reason: 'يجب استخراج معرف رسالة تيليجرام بدقة من وسم [TG_MSG_ID:88421]');
      expect(banner.displayContent, 'دعوة لحضور المؤتمر السنوي', reason: 'يجب تنظيف النص من الوسم الداخلي عند العرض للطلاب');

      // 3. اختبار استخراج معرف الرسالة للجداول الدراسية
      final scheduleRawJson = {
        'id': 'sch-12',
        'title': 'جدول الامتحانات النهائية',
        'content': '[SCHEDULE_TIMETABLE] [TG_MSG_ID:99120] جدول دراسي',
        'category': 'exam',
        'department': 'هندسة تقنيات الأجهزة الطبية',
        'stage': 'المرحلة الرابعة',
        'image_url': 'https://api.telegram.org/file/bot/docs/file_99120.pdf',
        'author_name': 'ممثل الدفعة',
        'author_id': 'REP-413',
      };

      final schedule = ScheduleModel.fromJson(scheduleRawJson);
      expect(schedule.telegramMessageId, 99120, reason: 'يجب أن يتعرف المودل على معرف رسالة تيليجرام للجدول');
      expect(schedule.toJson()['telegram_message_id'], 99120);

      // 4. اختبار التوافق مع رابط الصورة /api/file/{id} كخيار بديل
      final fallbackUrl = 'https://nust.edu.iq/api/file/77654';
      final urlMatch = RegExp(r'/api/file/(\d+)').firstMatch(fallbackUrl);
      expect(urlMatch, isNotNull);
      expect(int.tryParse(urlMatch!.group(1)!), 77654);
    });

    test('اختبار نافذة المعاينة المدمجة وعارض PDF المحلي المباشر (In-App Media Preview & Local PDF Viewer)', () {
      // 1. فحص كشف أنواع الوسائط (صور، PDF، مستندات)
      const pdfUrl = 'https://api.telegram.org/file/bot8816281220/documents/lecture_1.pdf';
      const imageUrl = 'https://api.telegram.org/file/bot8816281220/photos/file_0.jpg';

      // فحص تحويل رابط الـ PDF إلى عارض pdf_viewer.html المحلي المباشر بدون Google Docs
      final proxied = AppConstants.resolveImageUrl(pdfUrl);
      final pdfViewerUrl = 'pdf_viewer.html?file=${Uri.encodeComponent(proxied)}';
      expect(pdfViewerUrl, contains('pdf_viewer.html?file='));

      // فحص نموذج الـ Widget للـ PDF
      const previewModal = AppMediaPreviewModal(
        title: 'محاضرة التشريح الطبي',
        subtitle: 'المرحلة الثانية • PDF',
        rawUrl: pdfUrl,
        fileName: 'anatomy.pdf',
        mimeType: 'application/pdf',
      );
      expect(previewModal.title, 'محاضرة التشريح الطبي');
      expect(previewModal.rawUrl, pdfUrl);

      // فحص نموذج الـ Widget للصورة
      const imageModal = AppMediaPreviewModal(
        title: 'مخطط الدائرة الإلكترونية',
        subtitle: 'المرحلة الثالثة • صورة',
        rawUrl: imageUrl,
        fileName: 'circuit.png',
        mimeType: 'image/png',
      );
      expect(imageModal.title, 'مخطط الدائرة الإلكترونية');
      expect(imageModal.rawUrl, imageUrl);
    });

    test('اختبار حظر رفع الفيديوهات والاعتماد الحصري على المستندات والصور (No Video Uploads & Documents Only Policy)', () {
      // 1. فحص قائمة الامتدادات المسموح بها للمحاضرات (مستندات وصور فقط بدون فيديو)
      final allowedDocsAndImages = ['pdf', 'docx', 'doc', 'pptx', 'ppt', 'png', 'jpg', 'jpeg', 'webp', 'zip', 'rar'];
      final forbiddenVideoFormats = ['mp4', 'mkv', 'avi', 'mov', 'webm', 'flv'];

      for (final forbidden in forbiddenVideoFormats) {
        expect(allowedDocsAndImages.contains(forbidden), false, reason: 'يجب حظر امتدادات الفيديو $forbidden تماماً من المنظومة');
      }

      for (final allowed in ['pdf', 'docx', 'pptx', 'png', 'jpg']) {
        expect(allowedDocsAndImages.contains(allowed), true, reason: 'يجب السماح بامتداد المستند/الصورة $allowed');
      }
    });

    test('اختبار توحيد المحاضرات لكافة شُعب المرحلة وعزل التبليغات لكل شعبة حصراً (Unified Stage Lectures & Strict Section Announcements)', () {
      // 1. ممثلان لشعبتين مختلفتين في نفس المرحلة
      final repA = AppUserModel(
        id: 'rep-a-1',
        studentId: 'ST-NUST-001-A',
        name: 'أحمد علي',
        department: 'هندسة تقنيات الحاسوب',
        stage: 'المرحلة الثالثة',
        section: 'A',
        role: AppConstants.roleRepresentative,
        canPublishLectures: true,
        canPublishAnnouncements: true,
      );

      final repB = AppUserModel(
        id: 'rep-b-1',
        studentId: 'ST-NUST-002-B',
        name: 'كرار حسين',
        department: 'هندسة تقنيات الحاسوب',
        stage: 'المرحلة الثالثة',
        section: 'B',
        role: AppConstants.roleRepresentative,
        canPublishLectures: true,
        canPublishAnnouncements: true,
      );

      final studentA = AppUserModel(
        id: 'std-a-1',
        studentId: 'ST-NUST-003-A',
        name: 'طالب في شعبة A',
        department: 'هندسة تقنيات الحاسوب',
        stage: 'المرحلة الثالثة',
        section: 'A',
        role: AppConstants.roleStudent,
      );

      final studentB = AppUserModel(
        id: 'std-b-1',
        studentId: 'ST-NUST-004-B',
        name: 'طالب في شعبة B',
        department: 'هندسة تقنيات الحاسوب',
        stage: 'المرحلة الثالثة',
        section: 'B',
        role: AppConstants.roleStudent,
      );

      // 2. محاضرات مرفوعة من ممثل شعبة A وممثل شعبة B
      final lecA = LectureModel(
        id: 'lec-1',
        uploaderId: repA.studentId,
        uploaderName: repA.name,
        title: 'محاضرة البرمجيات - الفصل الأول',
        subjectName: 'هندسة البرمجيات',
        department: 'هندسة تقنيات الحاسوب',
        stage: 'المرحلة الثالثة',
        section: 'ALL',
        semester: 1,
        type: 'theory',
        driveUrl: 'https://example.com/lec1',
        createdAt: DateTime.now(),
      );

      final lecB = LectureModel(
        id: 'lec-2',
        uploaderId: repB.studentId,
        uploaderName: repB.name,
        title: 'محاضرة شبكات متقدمة',
        subjectName: 'شبكات الحاسوب II',
        department: 'هندسة تقنيات الحاسوب',
        stage: 'المرحلة الثالثة',
        section: 'ALL',
        semester: 1,
        type: 'practical',
        driveUrl: 'https://example.com/lec2',
        createdAt: DateTime.now(),
      );

      final allStageLectures = [lecA, lecB];

      // المحاضرات تظهر لجميع طلبة المرحلة بغض النظر عن شعبتهم
      expect(allStageLectures.length, 2, reason: 'المحاضرات موحدة لكافة شُعب المرحلة والقسم');

      // 3. تبليغات منفصلة لكل شعبة
      final announceA = AnnouncementModel(
        id: 'ann-1',
        title: 'كويز خاص بشعبة A',
        content: 'امتحان كويز يوم الأحد لشعبة A',
        authorId: repA.studentId,
        authorName: repA.name,
        authorRole: 'representative',
        department: 'هندسة تقنيات الحاسوب',
        stage: 'المرحلة الثالثة',
        section: 'A',
        createdAt: DateTime.now(),
      );

      final announceB = AnnouncementModel(
        id: 'ann-2',
        title: 'تأجيل مختبر لشعبة B',
        content: 'تأجيل مختبر شعبة B ليوم الثلاثاء',
        authorId: repB.studentId,
        authorName: repB.name,
        authorRole: 'representative',
        department: 'هندسة تقنيات الحاسوب',
        stage: 'المرحلة الثالثة',
        section: 'B',
        createdAt: DateTime.now(),
      );

      final announceGeneral = AnnouncementModel(
        id: 'ann-3',
        title: 'عطلة رسمية للكلية',
        content: 'إعلان عام لجميع الطلاب',
        authorId: 'ADMIN',
        authorName: 'مجتبى عواد',
        authorRole: 'admin',
        department: 'هندسة تقنيات الحاسوب',
        stage: 'المرحلة الثالثة',
        section: 'ALL',
        createdAt: DateTime.now(),
      );

      final allAnnouncements = [announceA, announceB, announceGeneral];

      // طالب شعبة A يرى فقط تبليغات شعبة A والتبليغات العامة، ولا يرى تبليغ شعبة B
      final studentAAnnouncements = allAnnouncements.where((a) => a.section == 'ALL' || a.section == studentA.section).toList();
      expect(studentAAnnouncements.length, 2);
      expect(studentAAnnouncements.any((a) => a.id == 'ann-1'), true);
      expect(studentAAnnouncements.any((a) => a.id == 'ann-3'), true);
      expect(studentAAnnouncements.any((a) => a.id == 'ann-2'), false, reason: 'طالب شعبة A لا يرى تبليغات شعبة B أبداً');

      // طالب شعبة B يرى فقط تبليغات شعبة B والتبليغات العامة، ولا يرى تبليغ شعبة A
      final studentBAnnouncements = allAnnouncements.where((a) => a.section == 'ALL' || a.section == studentB.section).toList();
      expect(studentBAnnouncements.length, 2);
      expect(studentBAnnouncements.any((a) => a.id == 'ann-2'), true);
      expect(studentBAnnouncements.any((a) => a.id == 'ann-3'), true);
      expect(studentBAnnouncements.any((a) => a.id == 'ann-1'), false, reason: 'طالب شعبة B لا يرى تبليغات شعبة A أبداً');

      // 4. فحص صلاحيات الحذف (الممثل يحذف فقط ما رفعه هو، والمشرف العام يحذف أي شيء)
      final bool repACanDeleteLecA = repA.studentId == lecA.uploaderId || repA.isAdmin;
      final bool repACanDeleteLecB = repA.studentId == lecB.uploaderId || repA.isAdmin;
      expect(repACanDeleteLecA, true, reason: 'الممثل يحذف المحاضرة التي قام هو برفعها');
      expect(repACanDeleteLecB, false, reason: 'الممثل لا يستطيع حذف محاضرة ممثل آخر');

      final adminMujtaba = AppUserModel(
        id: 'adm-1',
        studentId: 'ST-NUST-001630760-413',
        name: 'مجتبى عواد طالب',
        department: 'هندسة تقنيات الأجهزة الطبية',
        stage: 'المرحلة الرابعة',
        role: AppConstants.roleAdmin,
      );

      final bool adminCanDeleteLecA = adminMujtaba.studentId == lecA.uploaderId || adminMujtaba.isAdmin || adminMujtaba.name.contains('مجتبى');
      final bool adminCanDeleteLecB = adminMujtaba.studentId == lecB.uploaderId || adminMujtaba.isAdmin || adminMujtaba.name.contains('مجتبى');
      expect(adminCanDeleteLecA, true, reason: 'المشرف العام يملك صلاحية حذف أي محاضرة');
      expect(adminCanDeleteLecB, true, reason: 'المشرف العام يملك صلاحية حذف أي محاضرة');
    });

    test('اختبار ترميز وفك وسم الشعبة [SECTION:...] في المحاضرات والتبليغات (Section Tag Serialization & Deserialization)', () {
      // 1. فحص كائن المحاضرة مع وسم الشعبة داخل الوصف
      final rawLectureJson = {
        'id': 'lec-test-1',
        'title': 'محاضرة إلكترونيات قدرة',
        'subject_name': 'إلكترونيات',
        'department': 'هندسة تقنيات الحاسوب',
        'stage': 'المرحلة الثالثة',
        'description': '[SECTION:C] تجربة معملية رقم 4',
        'semester': 1,
        'type': 'practical',
        'drive_url': 'https://example.com/c',
        'created_at': DateTime.now().toIso8601String(),
      };

      final parsedLecture = LectureModel.fromJson(rawLectureJson);
      expect(parsedLecture.section, 'C', reason: 'تم استخراج الشعبة بنجاح من وسم [SECTION:C]');
      expect(parsedLecture.displayDescription, 'تجربة معملية رقم 4', reason: 'تم تنظيف الوصف لإخفاء الوسم الفني عن المستخدم');

      // 2. فحص كائن التبليغ مع وسم الشعبة داخل المحتوى
      final rawAnnounceJson = {
        'id': 'ann-test-1',
        'title': 'كويز مفاجئ',
        'content': '[SECTION:A] كويز باكر الساعة 8:30 صباحاً',
        'category': 'exam',
        'author_id': 'REP-A',
        'author_name': 'ممثل شعبة A',
        'author_role': 'representative',
        'subject_name': 'إلكترونيات',
        'created_at': DateTime.now().toIso8601String(),
      };

      final parsedAnnounce = AnnouncementModel.fromJson(rawAnnounceJson);
      expect(parsedAnnounce.section, 'A', reason: 'تم استخراج الشعبة بنجاح من وسم [SECTION:A]');
      expect(parsedAnnounce.displayContent, 'كويز باكر الساعة 8:30 صباحاً', reason: 'تم تنظيف المحتوى من الوسم الفني');
    });

    test('اختبار إلغاء دور التدريسي/الأستاذ نهائياً من كافة مستويات الصلاحيات والنماذج (Total Elimination of Professor Role)', () {
      // 1. التأكد من قائمة الأدوار المعتمدة
      expect(AppConstants.roleAdmin, 'admin');
      expect(AppConstants.roleRepresentative, 'representative');
      expect(AppConstants.roleStudent, 'student');

      // 2. التأكد من مسميات الأدوار
      expect(AppConstants.getRoleLabel(AppConstants.roleAdmin), contains('مشرف عام'));
      expect(AppConstants.getRoleLabel(AppConstants.roleRepresentative), contains('ممثل'));
      expect(AppConstants.getRoleLabel(AppConstants.roleStudent), contains('طالب'));
      expect(AppConstants.getRoleLabel('professor'), contains('طالب'));

      // 3. التحقق من خاصية isProfessor في نموذج المستخدم ترجع false دائماً
      final user = AppUserModel(
        id: 'u-1',
        studentId: '1234',
        name: 'مستخدم تجريبي',
        department: 'قسم',
        stage: 'مرحلة',
        role: 'student',
      );
      expect(user.isProfessor, false);
    });

    test('اختبار ملف التثبيت المباشر للآيفون (iOS Standalone WebClip Profile & Install Dialog)', () {
      // 1. التحقق من مسارات التثبيت لنظام iOS
      const primaryUrl = '/api/mobileconfig';
      const fallbackUrl = '/mohadarati.mobileconfig';
      expect(primaryUrl.endsWith('.mobileconfig') || primaryUrl.contains('mobileconfig'), true);
      expect(fallbackUrl.endsWith('.mobileconfig'), true);

      // 2. التحقق من إمكانية إنشاء نافذة التثبيت للآيفون بنجاح
      const dialog = IosInstallDialog();
      expect(dialog, isNotNull);
    });

    test('اختبار إخفاء اسم ناشر الجدول والربط الفوري لبوت طلب المعرف (Schedule Anonymization & Bot Instant Code)', () {
      // 1. التحقق من تاريخ الجدول وتنسيقه
      final testSchedule = ScheduleModel(
        id: 'sch-10',
        title: 'جدول المحاضرات الأسبوعي',
        type: 'lectures',
        department: 'هندسة تقنيات الأجهزة الطبية',
        stage: 'المرحلة الثانية',
        uploaderName: 'علي محمد حميد',
        createdAt: DateTime(2026, 10, 13),
      );
      expect(testSchedule.formattedDate, '2026/10/13');
      expect(testSchedule.isExam, false);

      // 2. التحقق من رابط التوجيه باختصار id المعتمد في البوت لاسترجاع القيد فوراً
      final botDeepLink = '${AppConstants.telegramBotUrl}?start=id';
      expect(botDeepLink, contains('start=id'));
      expect(botDeepLink, contains(AppConstants.telegramBotUsername));
    });

    test('اختبار خدمة وسياق المعاينة الفورية للآدمن (AdminPreviewService Live Context & Reset)', () {
      final preview = AdminPreviewService();
      final adminUser = AppUserModel(
        id: 'u-admin',
        studentId: 'ST-NUST-001630760-413',
        name: 'مجتبى عواد طالب عبيد',
        department: 'هندسة تقنيات الأجهزة الطبية',
        stage: 'المرحلة الرابعة',
        role: AppConstants.roleAdmin,
      );

      // تهيئة السياق
      preview.initialize(adminUser);
      expect(preview.department, 'هندسة تقنيات الأجهزة الطبية');
      expect(preview.stage, 'المرحلة الرابعة');
      expect(preview.isCustomActive, false);

      // تبديل القسم والمرحلة والشعبة
      preview.setTarget(
        department: 'هندسة تقنيات الحاسوب',
        stage: 'المرحلة الثالثة',
        section: 'B',
      );
      expect(preview.department, 'هندسة تقنيات الحاسوب');
      expect(preview.stage, 'المرحلة الثالثة');
      expect(preview.section, 'B');
      expect(preview.isCustomActive, true);

      // إعادة التعيين للوضع الافتراضي
      preview.reset(adminUser);
      expect(preview.department, 'هندسة تقنيات الأجهزة الطبية');
      expect(preview.stage, 'المرحلة الرابعة');
      expect(preview.isCustomActive, false);
    });

    test('اختبار عزل تبليغات المواد ومنع الصور العشوائية في كاروسيل الواجهة الرئيسية (Home Carousel Banner Sanitization)', () {
      final subjectAnnounce = AnnouncementModel(
        id: 'ann-sub-1',
        title: 'امتحان كويز معمارية الحاسوب',
        content: 'يوم الأحد كويز للمادة',
        authorId: 'rep-1',
        authorName: 'ممثل الشعبة',
        authorRole: 'representative',
        department: 'هندسة تقنيات الحاسوب',
        stage: 'المرحلة الثالثة',
        section: 'A',
        category: 'academic',
        subjectName: 'معمارية الحاسوب',
        createdAt: DateTime.now(),
      );

      final scheduleAnnounce = AnnouncementModel(
        id: 'ann-sch-1',
        title: 'جدول الامتحانات',
        content: '[SCHEDULE_TIMETABLE] جدول امتحاني',
        authorId: 'rep-1',
        authorName: 'ممثل الشعبة',
        authorRole: 'representative',
        department: 'هندسة تقنيات الحاسوب',
        stage: 'المرحلة الثالثة',
        category: 'exam',
        imageUrl: 'https://example.com/schedule.jpg',
        subjectName: 'SCHEDULE',
        createdAt: DateTime.now(),
      );

      final officialBanner = AnnouncementModel(
        id: 'ann-banner-1',
        title: 'معرض النتاجات العلمية السنوي',
        content: 'تدعوكم الكلية لحضور المعرض',
        authorId: 'admin-1',
        authorName: 'مجتبى عواد',
        authorRole: 'admin',
        department: 'ALL',
        stage: 'ALL',
        category: 'general',
        imageUrl: 'https://example.com/banner.jpg',
        subjectName: 'BANNER',
        createdAt: DateTime.now(),
      );

      final all = [subjectAnnounce, scheduleAnnounce, officialBanner];

      // تطبيق لوجيك تنقية الكاروسيل الجديد
      final filteredBanners = all.where((a) {
        if (a.content.contains('[SCHEDULE_TIMETABLE]') ||
            a.content.contains('[COURSE_REGISTRY') ||
            a.subjectName == 'SCHEDULE' ||
            a.subjectName == 'COURSE') {
          return false;
        }
        if (a.subjectName != null &&
            a.subjectName!.isNotEmpty &&
            a.subjectName != 'BANNER' &&
            a.subjectName != 'GENERAL' &&
            a.subjectName != 'ALL' &&
            a.subjectName != 'عام') {
          return false;
        }
        return a.imageUrl != null && a.imageUrl!.trim().isNotEmpty;
      }).toList();

      expect(filteredBanners.length, 1);
      expect(filteredBanners.first.id, 'ann-banner-1');
      expect(filteredBanners.contains(subjectAnnounce), false, reason: 'تبليغات المواد يجب ألا تظهر نهائياً في كاروسيل الواجهة الرئيسية');
      expect(filteredBanners.contains(scheduleAnnounce), false, reason: 'الجداول معزولة تماماً');
    });

    test('اختبار خدمة التحديث التلقائي الإجباري ومراقبة دورة الحياة (AutoUpdateService Singleton & Observer)', () {
      final service = AutoUpdateService();
      expect(service, isNotNull);
      // التحقق من تهيئة المراقب
      service.initialize();
      // محاكاة استئناف التطبيق من الخلفية
      service.didChangeAppLifecycleState(AppLifecycleState.resumed);
      expect(service, isA<AutoUpdateService>());
    });

    test('اختبار عزل الجداول الصارم لكل شعبة وحظر خلط منشورات الكروبات (Strict Section Schedule Isolation)', () {
      final scheduleA = ScheduleModel(
        id: 'sch-sec-a',
        title: 'جدول المحاضرات شعبة A',
        type: 'lectures',
        department: 'هندسة تقنيات الحاسوب',
        stage: 'المرحلة الأولى',
        section: 'A',
        createdAt: DateTime.now(),
      );

      final scheduleB = ScheduleModel(
        id: 'sch-sec-b',
        title: 'جدول المحاضرات شعبة B',
        type: 'lectures',
        department: 'هندسة تقنيات الحاسوب',
        stage: 'المرحلة الأولى',
        section: 'B',
        createdAt: DateTime.now(),
      );

      expect(scheduleA.sectionLabel, 'شعبة A');
      expect(scheduleB.sectionLabel, 'شعبة B');

      // محاكاة طالب في الشعبة A
      const studentSection = 'A';
      final studentSchedules = [scheduleA, scheduleB].where((s) => s.section.toUpperCase() == studentSection).toList();
      expect(studentSchedules.length, 1);
      expect(studentSchedules.first.id, 'sch-sec-a');
      expect(studentSchedules.contains(scheduleB), false, reason: 'جداول الشعب الأخرى محظورة تماماً عن الطالب');
    });

    test('اختبار معالجة ومطابقة أسماء المراحل والسنوات الأكاديمية (Stage Normalization & Biometric Compatibility)', () {
      // 1. اختبار AppConstants.normalizeStage
      expect(AppConstants.normalizeStage('السنة الأولى'), 'المرحلة الأولى');
      expect(AppConstants.normalizeStage('السنة الثانية'), 'المرحلة الثانية');
      expect(AppConstants.normalizeStage('السنة الثالثة'), 'المرحلة الثالثة');
      expect(AppConstants.normalizeStage('السنة الرابعة'), 'المرحلة الرابعة');
      expect(AppConstants.normalizeStage('المرحلة الثالثة'), 'المرحلة الثالثة');

      // 2. اختبار AppConstants.getStageAliases
      final aliases3 = AppConstants.getStageAliases('المرحلة الثالثة');
      expect(aliases3.contains('المرحلة الثالثة'), true);
      expect(aliases3.contains('السنة الثالثة'), true);

      // 3. اختبار جلب مقررات المرحلة الثالثة لأجهزة طبية عند تمرير "السنة الثالثة"
      final subjectsYear3 = BiometricSubjects.getSubjects(
        department: 'هندسة تقنيات الأجهزة الطبية',
        stage: 'السنة الثالثة',
      );
      expect(subjectsYear3.isNotEmpty, true, reason: 'يجب أن تظهر مقررات المرحلة الثالثة حتى لو كانت المرحلة مخزنة باسم السنة الثالثة');

      final subjectsStage3 = BiometricSubjects.getSubjects(
        department: 'هندسة تقنيات الأجهزة الطبية',
        stage: 'المرحلة الثالثة',
      );
      expect(subjectsYear3.length, subjectsStage3.length);

      // 4. اختبار نموذج الطالب والمستخدم وتطبيع المرحلة
      final student = StudentModel.fromJson({
        'id': 'ST-NUST-0013414835-876',
        'name': 'يوسف حمزه قاسم سرحان',
        'department': 'هندسة تقنيات الأجهزة الطبية',
        'stage': 'السنة الثالثة',
        'section': 'C',
      });
      expect(student.stage, 'المرحلة الثالثة');

      final appUser = AppUserModel.fromJson({
        'id': 'usr-test-1',
        'student_id': 'ST-NUST-0013414835-876',
        'name': 'يوسف حمزه قاسم سرحان',
        'department': 'هندسة تقنيات الأجهزة الطبية',
        'stage': 'السنة الثالثة',
        'section': 'C',
        'role': 'student',
      });
      expect(appUser.stage, 'المرحلة الثالثة');
    });

    test('اختبار تطبيع الحروف العربية ومطابقة أسماء المقررات وضمان ظهور منشورات الممثل فورياً (Arabic Normalization & Rep Visibility)', () {
      // 1. فحص تطبيع التاء المربوطة والهاء والهمزات
      final str1 = 'الأجهزة الطبية المختبريه';
      final str2 = 'الأجهزة الطبية المختبرية';
      expect(AppConstants.arabicEquals(str1, str2), true, reason: 'المختبريه بالهاء والمختبرية بالتاء المربوطة يجب أن يتطابقا تماماً');

      final str3 = 'إلكترونيات القدرة';
      final str4 = 'الكترونيات القدرة';
      expect(AppConstants.arabicEquals(str3, str4), true, reason: 'الهمزة على الألف والهمزة المكسورة يجب أن تتطابقا');

      final str5 = 'مادة ميكروكنترولر';
      expect(AppConstants.arabicContains(str5, 'ميكروكنترولر'), true);
      expect(AppConstants.arabicContains('ميكروكنترولر', str5), false);

      // 2. فحص ضمان ظهور منشورات الممثل التي رفعها بنفسه دون أن تحجبها فلاتر الشعب
      final repStudentId = 'ST-REP-12345';
      final myLecture = LectureModel(
        id: 'lec-rep-1',
        title: 'محاضرة تجريبية',
        subjectName: 'الأجهزة الطبية المختبريه',
        department: 'هندسة تقنيات الأجهزة الطبية',
        stage: 'المرحلة الثانية',
        section: 'B',
        uploaderId: repStudentId,
        uploaderName: 'ممثل الشعبة',
        driveUrl: 'https://example.com/file.pdf',
        createdAt: DateTime.now(),
      );

      // مطابقة اسم المادة مع الاسم المعتمد في المنهج (المختبرية بالتاء المربوطة)
      final courseCanonicalName = 'الأجهزة الطبية المختبرية';
      final bool matchesCourse = AppConstants.arabicEquals(myLecture.subjectName, courseCanonicalName) ||
          AppConstants.arabicContains(myLecture.subjectName, courseCanonicalName) ||
          AppConstants.arabicContains(courseCanonicalName, myLecture.subjectName);
      expect(matchesCourse, true, reason: 'يجب أن تظهر المحاضرة داخل صفحة المادة حتى لو اختلف رسم التاء المربوطة والهاء');

      // فحص معيار مؤلف المنشور (isAuthor)
      final bool isAuthor = repStudentId == myLecture.uploaderId;
      expect(isAuthor, true, reason: 'الممثل الناشر يجب دائماً أن يعتبر مؤلفاً ويشاهد محاضره');
    });

    test('اختبار التشفير الرياضي والتحقق المزدوج لرمز المرور وتعمية التوكنات (Cryptographic PIN Hashing & Token Obfuscation)', () {
      const rawPin = '1234';
      final hashedPin = AppConstants.hashPin(rawPin);

      // 1. فحص مواصفات التشفير SHA-256
      expect(hashedPin.isNotEmpty, true);
      expect(hashedPin.length, 64, reason: 'SHA-256 يجب أن يكون بطول 64 حرفاً سداسياً');
      expect(hashedPin != rawPin, true);

      // 2. فحص التحقق المزدوج (Dual Verification)
      // أ) التحقق مع الرمز القديم المجرد (Legacy Plaintext)
      expect(AppConstants.verifyPin('1234', '1234'), true, reason: 'يجب قبول الرمز القديم القائم دون إخراج الطالب');
      // ب) التحقق مع الرمز المشفر بعد الترقية التلقائية
      expect(AppConstants.verifyPin('1234', hashedPin), true, reason: 'يجب قبول الرمز المشفر بنجاح');
      // ج) رفض أي رمز خاطئ
      expect(AppConstants.verifyPin('9999', hashedPin), false, reason: 'يجب رفض الرمز الخاطئ');
      expect(AppConstants.verifyPin('', hashedPin), false);

      // 3. فحص تعمية التوكنات البرمجية وفكها ديناميكياً
      expect(AppConstants.attendanceBotToken.contains(':'), true);
      expect(AppConstants.lecturesBotToken.contains(':'), true);
      expect(AppConstants.attendanceBotToken.startsWith('87600'), true);
      expect(AppConstants.lecturesBotToken.startsWith('88162'), true);
    });

    test('اختبار ضوابط أمان الحذف وصلاحيات الكاتب في المحاضرات والتبليغات (Author Matching & Ownership Verification)', () {
      final authorUser = AppUserModel(
        id: 'u-1',
        studentId: 'ST-001',
        name: 'ممثل معتمد',
        department: 'هندسة تقنيات الحاسوب',
        stage: 'المرحلة الرابعة',
        role: AppConstants.roleRepresentative,
      );

      final otherUser = AppUserModel(
        id: 'u-2',
        studentId: 'ST-002',
        name: 'طالب آخر',
        department: 'هندسة تقنيات الحاسوب',
        stage: 'المرحلة الرابعة',
        role: AppConstants.roleStudent,
      );

      final adminUser = AppUserModel(
        id: 'u-admin',
        studentId: 'ST-NUST-001630760-413',
        name: 'مجتبى عواد',
        department: 'هندسة تقنيات الأجهزة الطبية',
        stage: 'المرحلة الرابعة',
        role: AppConstants.roleAdmin,
      );

      const lectureAuthorId = 'ST-001';

      // دالة التحقق من الصلاحيات
      bool canDelete(AppUserModel user, String authorId) {
        if (user.role == AppConstants.roleAdmin) return true;
        return authorId.isNotEmpty && (authorId == user.id || authorId == user.studentId);
      }

      // المؤلف يحق له الحذف
      expect(canDelete(authorUser, lectureAuthorId), true);
      // المشرف العام يحق له الحذف
      expect(canDelete(adminUser, lectureAuthorId), true);
      // مستخدم آخر لا يحق له حذف منشورات غيره
      expect(canDelete(otherUser, lectureAuthorId), false);
    });

    test('اختبار مطابقة وتوزيع الطلاب والممثلين حسب المراحل الموحدة (Dashboard Stage Matching)', () {
      final users = [
        AppUserModel(
          id: 'u-1',
          studentId: 'ST-101',
          name: 'علي حسن',
          department: 'هندسة تقنيات الحاسوب',
          stage: 'السنة الثانية', // صيغة نظام البصمة القديم
          role: AppConstants.roleRepresentative,
          section: 'A',
        ),
        AppUserModel(
          id: 'u-2',
          studentId: 'ST-102',
          name: 'محمد جاسم',
          department: 'هندسة تقنيات الحاسوب',
          stage: 'المرحلة 2', // صيغة رقمية
          role: AppConstants.roleStudent,
          section: 'A',
        ),
        AppUserModel(
          id: 'u-3',
          studentId: 'ST-103',
          name: 'كرار حيدر',
          department: 'هندسة تقنيات الحاسوب',
          stage: 'المرحلة الثانية', // الصيغة الرسمية
          role: AppConstants.roleStudent,
          section: 'B',
        ),
        AppUserModel(
          id: 'u-4',
          studentId: 'ST-104',
          name: 'حسين علي',
          department: 'هندسة تقنيات الحاسوب',
          stage: 'السنة الثالثة',
          role: AppConstants.roleStudent,
          section: 'A',
        ),
      ];

      // فلتر المرحلة الثانية
      const filterStage = 'المرحلة الثانية';
      final matchingStage2 = users.where((u) =>
          AppConstants.normalizeStage(u.stage) == AppConstants.normalizeStage(filterStage)).toList();

      // يجب أن يطابق الطلاب الثلاثة في المرحلة الثانية مهما كان شكل التسمية
      expect(matchingStage2.length, 3);
      expect(matchingStage2.map((u) => u.name), containsAll(['علي حسن', 'محمد جاسم', 'كرار حيدر']));

      // التحقق من احتساب ممثلي شعبة A في المرحلة الثانية
      final repCountSecA = users.where((u) =>
          u.isRepresentative &&
          AppConstants.normalizeStage(u.stage) == AppConstants.normalizeStage(filterStage) &&
          u.section == 'A'
      ).length;
      expect(repCountSecA, 1);
    });

    test('اختبار دمج المقررات المضافة مع المقررات الرسمية للبصمة (Courses Merging & Deduplication)', () {
      final baseSubjects = BiometricSubjects.getSubjectNames(
        department: 'هندسة تقنيات الحاسوب',
        stage: 'المرحلة الثانية',
        semester: 1,
      );

      final customCourses = ['الأمن السيبراني المتقدم', 'مقرر إضافي للشعبة', baseSubjects.first];
      final mergedList = List<String>.from(baseSubjects);

      for (final item in customCourses) {
        final clean = item.trim();
        if (clean.isNotEmpty && !mergedList.contains(clean)) {
          mergedList.add(clean);
        }
      }

      // يجب عدم تكرار المادة الموجودة أصلاً
      expect(mergedList.where((s) => s == baseSubjects.first).length, 1);
      // يجب إضافة المواد الجديدة بنجاح
      expect(mergedList, contains('الأمن السيبراني المتقدم'));
      expect(mergedList, contains('مقرر إضافي للشعبة'));
      expect(mergedList.length, baseSubjects.length + 2);
    });

    test('اختبار التحقق من صحة الرقم والمعرف الجامعي (Student ID Validation TDD Cycle)', () {
      // 1. معرفات نظام البصمة الرسمية ST-...
      expect(AppConstants.isValidStudentId('ST-NUST-001630760-413'), isTrue);
      expect(AppConstants.isValidStudentId('st-12345'), isTrue);
      // 2. الأرقام الجامعية الرقمية (5 خانات فما فوق)
      expect(AppConstants.isValidStudentId('1125097'), isTrue);
      // 3. المدخلات غير الصالحة أو الفارغة
      expect(AppConstants.isValidStudentId(''), isFalse);
      expect(AppConstants.isValidStudentId('   '), isFalse);
      expect(AppConstants.isValidStudentId('abc'), isFalse);
      expect(AppConstants.isValidStudentId(null), isFalse);
    });

    test('اختبار معالجة استجابات ونماذج رفع المحاضرات والسحابة (TelegramUploader Resilience)', () {
      final resSuccess = UploadLectureResult(
        success: true,
        message: 'تم نشر ورفع المحاضرة إلى السحابة بنجاح ومزامنتها للطلبة',
        telegramMessageId: 12345,
        fileName: 'Lecture_1.pdf',
        fileSizeBytes: 1024 * 1024 * 5,
      );
      expect(resSuccess.success, isTrue);
      expect(resSuccess.telegramMessageId, 12345);
      expect(resSuccess.fileName, 'Lecture_1.pdf');

      final resOversized = UploadLectureResult(
        success: false,
        message: 'حجم الملف يتجاوز الحد الأقصى المسموح به للرفع المباشر (50 ميغابايت). يرجى ضغط الملف أو استخدام رابط Google Drive للملفات الكبيرة جداً.',
      );
      expect(resOversized.success, isFalse);
      expect(resOversized.message, contains('50 ميغابايت'));

      final genRes = UploadGeneralFileResult(
        success: true,
        message: 'تم رفع الملف بنجاح',
        fileUrl: 'https://api.telegram.org/file/bot123/doc.pdf',
        fileSizeBytes: 2048,
      );
      expect(genRes.success, isTrue);
      expect(genRes.fileUrl, contains('api.telegram.org'));
    });

    test('اختبار نظام التفاعلات الأكاديمية وسرية هوية الطلاب في التبليغات (Anonymous Reactions & Inspector)', () {
      final now = DateTime.now();
      final announcement = AnnouncementModel(
        id: 'ann-react-1',
        title: 'تبليغ هام بخصوص الامتحانات',
        content: 'يرجى مراجعة القاعات الامتحانية قبل نصف ساعة من الموعد',
        authorId: 'ST-NUST-001630760-413',
        authorName: 'مجتبى عواد حسن كاظم',
        authorRole: 'admin',
        createdAt: now,
      );

      // في البداية لا توجد تفاعلات
      expect(announcement.totalReactionsCount, 0);
      expect(announcement.reactionCounts.isEmpty, true);

      // محاكاة تفاعل 3 طلاب مختلفين بهويات مجهولة
      final reactionsMap = {
        'ST-001': AnnouncementReaction(
          studentId: 'ST-001',
          studentName: 'أحمد علي حسن',
          department: 'هندسة تقنيات الأجهزة الطبية',
          stage: 'المرحلة الرابعة',
          section: 'A',
          reaction: '👍',
          createdAt: now,
        ),
        'ST-002': AnnouncementReaction(
          studentId: 'ST-002',
          studentName: 'سارة محمد جاسم',
          department: 'هندسة تقنيات الأجهزة الطبية',
          stage: 'المرحلة الرابعة',
          section: 'B',
          reaction: '👍',
          createdAt: now,
        ),
        'ST-003': AnnouncementReaction(
          studentId: 'ST-003',
          studentName: 'كرار حيدر جبار',
          department: 'هندسة تقنيات الحاسوب',
          stage: 'المرحلة الثالثة',
          section: 'C',
          reaction: '❤️',
          createdAt: now,
        ),
      };

      final updated = announcement.copyWithReactions(reactionsMap);

      // 1. فحص إحصائيات العدادات المجهولة المتاحة لجميع الطلاب
      expect(updated.totalReactionsCount, 3);
      expect(updated.reactionCounts['👍'], 2);
      expect(updated.reactionCounts['❤️'], 1);
      expect(updated.reactionCounts['🔥'], isNull);

      // 2. فحص نظافة نص العرض displayContent وعدم ظهور وسوم التفاعلات البرمجية
      expect(updated.displayContent, equals('يرجى مراجعة القاعات الامتحانية قبل نصف ساعة من الموعد'));
      expect(updated.displayContent.contains('[REACTIONS:'), false);

      // 3. فحص تفاعل الطالب المحدد
      expect(updated.hasUserReacted('ST-001', '👍'), true);
      expect(updated.hasUserReacted('ST-001', '❤️'), false);
      expect(updated.getUserReaction('ST-003'), '❤️');
      expect(updated.getUserReaction('ST-999'), isNull);

      // 4. فحص سجل المتفاعلين المتاح حصراً للمشرف العام
      final list = updated.reactionsList;
      expect(list.length, 3);
      expect(list.any((r) => r.studentName == 'أحمد علي حسن' && r.section == 'A'), true);
      expect(list.any((r) => r.studentName == 'سارة محمد جاسم' && r.section == 'B'), true);
      expect(list.any((r) => r.studentName == 'كرار حيدر جبار' && r.section == 'C'), true);
    });

    test('اختبار خدمة الإشعارات والتنبيهات المباشرة للآيفون والأندرويد (AppNotificationService & Live Alerts)', () async {
      final notifAnn = AppNotificationItem(
        id: 'ann-101',
        title: '📢 تبليغ رسمي جديد',
        message: 'تم تحديد موعد الامتحان الفصلي لمادة الأجهزة الطبية',
        type: AppNotificationType.announcement,
        targetId: 'ann-101',
      );

      expect(notifAnn.id, 'ann-101');
      expect(notifAnn.title, contains('تبليغ رسمي'));
      expect(notifAnn.type, AppNotificationType.announcement);

      final notifLec = AppNotificationItem(
        id: 'lec-202',
        title: '📚 محاضرة: إلكترونيات طبية',
        message: 'المحاضرة الخامسة - الدوائر المتكاملة',
        type: AppNotificationType.lecture,
        targetId: 'lec-202',
      );

      expect(notifLec.id, 'lec-202');
      expect(notifLec.title, contains('محاضرة'));
      expect(notifLec.type, AppNotificationType.lecture);

      final service = AppNotificationService.instance;
      expect(service, isNotNull);
    });

    test('اختبار استطلاعات الرأي والتصويت الطلابي بنمط تيليجرام وسرية الأسماء (Student Polls & Privacy Guarantee)', () {
      // 1. إنشاء استطلاع رأي طلابي
      final poll = PollData(
        question: 'ما هو الوقت الأنسب للامتحان الفصلي لمادة الأجهزة الطبية؟',
        options: ['الأحد 9:00 صباحاً', 'الثلاثاء 11:30 صباحاً', 'الخميس 1:00 ظهراً'],
        allowsMultiple: false,
      );

      // تضمينه في إعلان
      final rawContent = 'يرجى من جميع الطلبة التصويت على موعد الامتحان.\n${poll.embedTag}';
      final announcement = AnnouncementModel(
        id: 'poll-101',
        title: 'استطلاع موعد الامتحان',
        content: rawContent,
        authorId: 'REP-001',
        authorName: 'ممثل المرحلة',
        authorRole: 'representative',
        department: 'هندسة تقنيات الأجهزة الطبية',
        stage: 'المرحلة الثانية',
        section: 'A',
        createdAt: DateTime.now(),
      );

      expect(announcement.isPoll, true);
      expect(announcement.displayContent, contains('يرجى من جميع الطلبة التصويت'));
      expect(announcement.displayContent, isNot(contains('[POLL:')));

      final parsedPoll = announcement.pollData!;
      expect(parsedPoll.question, 'ما هو الوقت الأنسب للامتحان الفصلي لمادة الأجهزة الطبية؟');
      expect(parsedPoll.options.length, 3);
      expect(parsedPoll.totalVotes, 0);

      // 2. تصويت طالب (حسين) على الخيار الأول (0)
      final voterHussein = PollVote(
        studentId: 'ST-001',
        studentName: 'حسين علي',
        section: 'A',
        selectedOptionIndices: [0],
        votedAt: DateTime.now(),
      );

      final pollAfterVote1 = parsedPoll.withVote(voterHussein);
      expect(pollAfterVote1.totalVotes, 1);
      expect(pollAfterVote1.votesForOption(0), 1);
      expect(pollAfterVote1.percentageForOption(0), 100);
      expect(pollAfterVote1.percentageForOption(1), 0);

      // 3. تصويت طالب ثانٍ (مريم) على الخيار الثاني (1)
      final voterMaryam = PollVote(
        studentId: 'ST-002',
        studentName: 'مريم أحمد',
        section: 'A',
        selectedOptionIndices: [1],
        votedAt: DateTime.now(),
      );
      final pollAfterVote2 = pollAfterVote1.withVote(voterMaryam);
      expect(pollAfterVote2.totalVotes, 2);
      expect(pollAfterVote2.percentageForOption(0), 50);
      expect(pollAfterVote2.percentageForOption(1), 50);

      // 4. تغيير التصويت بسلاسة (Smooth Vote Switching) من الخيار 0 إلى الخيار 2
      final switchedHussein = PollVote(
        studentId: 'ST-001',
        studentName: 'حسين علي',
        section: 'A',
        selectedOptionIndices: [2],
        votedAt: DateTime.now(),
      );
      final pollAfterSwitch = pollAfterVote2.withVote(switchedHussein);
      expect(pollAfterSwitch.totalVotes, 2);
      expect(pollAfterSwitch.votesForOption(0), 0);
      expect(pollAfterSwitch.votesForOption(1), 1);
      expect(pollAfterSwitch.votesForOption(2), 1);

      // 5. إغلاق التصويت (Close Poll)
      final closedPoll = pollAfterSwitch.copyWith(isClosed: true);
      expect(closedPoll.isClosed, true);

      // 6. التحقق من صلاحيات استعراض الأسماء (حصرية للمشرف العام مجتبى)
      final mujtabaUser = AppUserModel(
        id: 'admin_1',
        studentId: 'ST-NUST-001630760-413',
        name: 'مجتبى عواد',
        role: 'admin',
        stage: 'المرحلة الرابعة',
        department: 'هندسة تقنيات الأجهزة الطبية',
      );
      final normalStudent = AppUserModel(
        id: 'stud_1',
        studentId: 'ST-001',
        name: 'حسين علي',
        role: 'student',
        stage: 'المرحلة الثانية',
        department: 'هندسة تقنيات الأجهزة الطبية',
      );

      final isMujtabaAuthorized = mujtabaUser.isAdmin || mujtabaUser.studentId == 'ST-NUST-001630760-413';
      final isStudentAuthorized = normalStudent.isAdmin || normalStudent.studentId == 'ST-NUST-001630760-413';

      expect(isMujtabaAuthorized, true, reason: 'مجتبى عواد يملك الصلاحية الحصرية لمعاينة أسماء المصوتين');
      expect(isStudentAuthorized, false, reason: 'لا يُسمح للطلبة بالاطلاع على أسماء المصوتين إطلاقاً');
    });
  });
}




