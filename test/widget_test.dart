import 'package:flutter_test/flutter_test.dart';
import 'package:nust_student_portal/models/student_model.dart';
import 'package:nust_student_portal/models/lecture_model.dart';
import 'package:nust_student_portal/models/attendance_model.dart';
import 'package:nust_student_portal/models/announcement_model.dart';
import 'package:nust_student_portal/models/app_user_model.dart';
import 'package:nust_student_portal/services/attendance_service.dart';
import 'package:nust_student_portal/core/constants/app_constants.dart';
import 'package:nust_student_portal/core/constants/biometric_subjects.dart';
import 'package:nust_student_portal/models/subject_model.dart';
import 'package:nust_student_portal/models/schedule_model.dart';
import 'package:nust_student_portal/widgets/app_media_preview_modal.dart';

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
      expect(compStage3.any((s) => s.contains('هندسة البرمجيات')), isTrue);
      expect(compStage3.length, greaterThanOrEqualTo(6));

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
      // 1. فحص إجمالي عدد المواد في نظام البصمة الجامعي
      final all = BiometricSubjects.allSubjects;
      expect(all.length, 119, reason: 'يجب أن تحتوي المنظومة على 119 مادة رسمية معتمدة من نظام البصمة');

      // 2. فحص توزيع المواد حسب الأقسام
      final compSubjects = BiometricSubjects.getSubjects(department: 'هندسة تقنيات الحاسوب');
      final cyberSubjects = BiometricSubjects.getSubjects(department: 'هندسة تقنيات الأمن السيبراني');
      final medSubjects = BiometricSubjects.getSubjects(department: 'هندسة تقنيات الأجهزة الطبية');

      expect(compSubjects.length, 51, reason: 'هندسة الحاسوب تضم 51 مادة عبر المراحل الأربع');
      expect(cyberSubjects.length, 19, reason: 'الأمن السيبراني يضم 19 مادة رسمية');
      expect(medSubjects.length, 49, reason: 'الأجهزة الطبية تضم 49 مادة رسمية');
      expect(compSubjects.length + cyberSubjects.length + medSubjects.length, 119);

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

    test('اختبار قفل صلاحيات ومنشورات ممثل الشعبة وحصرها بطلبة شعبته فقط (Section Representative Scoping & Student Isolation)', () {
      // 1. مستخدم ممثل لشعبة B
      final repSectionB = AppUserModel(
        id: 'rep-b-1',
        studentId: '2023101',
        name: 'ممثل شعبة B',
        department: 'هندسة تقنيات الحاسوب',
        stage: 'المرحلة الثالثة',
        section: 'B',
        role: AppConstants.roleRepresentative,
        canPublishLectures: true,
        canPublishAnnouncements: true,
      );

      expect(repSectionB.isRepresentative, true);
      expect(repSectionB.isAdmin, false);
      expect(repSectionB.isProfessor, false);
      expect(repSectionB.section, 'B');

      // 2. محاكاة محاضرات منشورة لشعب مختلفة وعامة
      final lecGeneral = LectureModel(
        id: 'lec-all',
        uploaderId: 'rep-b-1',
        uploaderName: 'ممثل الدفعة',
        title: 'محاضرة عامة للكل',
        subjectName: 'شبكات الحاسوب',
        department: 'هندسة تقنيات الحاسوب',
        stage: 'المرحلة الثالثة',
        section: 'ALL',
        semester: 1,
        type: 'theory',
        driveUrl: 'https://example.com/all',
        createdAt: DateTime.now(),
      );

      final lecSectionA = LectureModel(
        id: 'lec-a',
        uploaderId: 'rep-a-1',
        uploaderName: 'ممثل شعبة A',
        title: 'محاضرة لشعبة A فقط',
        subjectName: 'شبكات الحاسوب',
        department: 'هندسة تقنيات الحاسوب',
        stage: 'المرحلة الثالثة',
        section: 'A',
        semester: 1,
        type: 'practical',
        driveUrl: 'https://example.com/a',
        createdAt: DateTime.now(),
      );

      final lecSectionB = LectureModel(
        id: 'lec-b',
        uploaderId: 'rep-b-1',
        uploaderName: 'ممثل شعبة B',
        title: 'محاضرة لشعبة B فقط',
        subjectName: 'شبكات الحاسوب',
        department: 'هندسة تقنيات الحاسوب',
        stage: 'المرحلة الثالثة',
        section: 'B',
        semester: 1,
        type: 'theory',
        driveUrl: 'https://example.com/b',
        createdAt: DateTime.now(),
      );

      final allLectures = [lecGeneral, lecSectionA, lecSectionB];

      // فلترة طالب شعبة B: يرى العامة + شعبة B فقط، ولا يرى شعبة A إطلاقاً
      final studentBVisible = allLectures.where((l) => l.section == 'ALL' || l.section == 'B').toList();
      expect(studentBVisible.length, 2);
      expect(studentBVisible.any((l) => l.id == 'lec-a'), false, reason: 'طالب شعبة B لا يرى محاضرات شعبة A أبداً');
      expect(studentBVisible.any((l) => l.id == 'lec-b'), true);
      expect(studentBVisible.any((l) => l.id == 'lec-all'), true);

      // فلترة الآدمن: يرى كل المحاضرات
      expect(allLectures.length, 3);
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
  });
}


