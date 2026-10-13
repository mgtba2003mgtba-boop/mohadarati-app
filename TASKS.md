# مهام مشروع تطبيق الكلية الجامعي المتكامل (NUST College Student Portal)

## 📌 قائمة المهام التنفيذية (TASKS.md)

- [x] **المرحلة 1: تحليل وتجهيز البنية التحتية وقاعدة البيانات (Supabase)**
  - [x] كتابة ملف هجرة قاعدة البيانات `supabase_migration.sql` لإنشاء جداول `app_users`, `announcements`, `lectures`, `subjects`, وسياسات الأمان RLS والصلاحيات وتطبيقه بنجاح على قاعدة البيانات الحية.
  - [x] كتابة واختبار سكربت استعلام Supabase والتحقق الفعلي من جداول الطلاب `students` وسجلات الحضور `attendance_records` الحالية.

- [x] **المرحلة 2: إعداد بيئة ومكتبات تطبيق فلاتر (Flutter Architecture & Dependencies)**
  - [x] إعداد `pubspec.yaml` الشامل بكافة المكتبات الأساسية (`supabase_flutter`, `google_fonts`, `url_launcher`, `shared_preferences`, `intl`, `cached_network_image`, `qr_flutter`).
  - [x] ضبط إعدادات النشر لمتجر Google Play (`AndroidManifest.xml`, permissions, url schemes).
  - [x] ضبط إعدادات النشر لمتجر Apple App Store (`Info.plist`, `LSApplicationQueriesSchemes`, Display Name).

- [x] **المرحلة 3: طبقة النماذج والخدمات (Models & Services Layer)**
  - [x] نمذجة البيانات `StudentModel`, `AppUserModel`, `AttendanceRecordModel`, `OverallAttendanceSummary`, `AnnouncementModel`, `LectureModel`.
  - [x] خدمة Supabase المركزية `SupabaseService` (المصادقة، جلب قيد الطالب عبر كود التيليجرام، تسجيل الدخول/إنشاء الحساب).
  - [x] خدمة الحضور والغياب `AttendanceService` (حساب نسب الحضور والغياب الإجمالية ولكل مادة من سجلات نظام الحضور، والإنذارات الأكاديمية).
  - [x] خدمة نشر وإدارة المحاضرات بروابط Google Drive والإعلانات.
  - [x] خدمة إدارة الصلاحيات والترقيات لممثلي الدفع والأساتذة.

- [x] **المرحلة 4: واجهات تجربة المستخدم وتصميم الشاشات (UI/UX Pages)**
  - [x] شاشة البداية والتحميل التلقائي للجلسة `SplashScreen`.
  - [x] شاشة الترحيب والتسجيل بالمعرف الجامعي `OnboardingScreen` (إدخال الكود المأخوذ من بوت التليجرام، جلب بيانات الطالب، إنشاء الحساب ورمز PIN).
  - [x] شاشة تسجيل الدخول السريع `LoginScreen`.
  - [x] شاشة الرئيسية والبطاقة الجامعية الذكية `HomeScreen` (عرض نسبة الحضور، كود QR، إحصائيات سريعة).
  - [x] شاشة الحضور والغياب التفصيلية `AttendanceScreen` (تفاصيل المواد، نسب الغياب، الإنذارات الأكاديمية، سجل فحص الوجوه).
  - [x] شاشة الإعلانات التفاعلية `AnnouncementsScreen` (تصفية حسب القسم/المرحلة/التصنيف، قراءة التفاصيل).
  - [x] شاشة المحاضرات والمقررات `LecturesScreen` (تصنيف حسب القسم/المرحلة/الفصل/نظري وعملي، فتح روابط Google Drive مباشرة، بحث وتصفية).
  - [x] لوحة تحكم المشرفين وممثلي الدفع `DashboardScreen` (نشر محاضرة برابط Google Drive، نشر إعلان، ترقية مستخدمين، إدارة المحتوى).
  - [x] شاشة الملف الشخصي والإعدادات `ProfileScreen`.

- [x] **المرحلة 5: المراجعة والاختبار والتحقق (Audit & Verification)**
  - [x] فحص كود Dart والتحقق من سلامة الأنواع عبر `dart analyze` بنجاح (Exit code 0).
  - [x] كتابة وتشغيل حزمة الاختبارات الشاملة `flutter test` واجتياز كافة الاختبارات بنجاح (Exit code 0).
  - [x] توثيق خطوات النشر على Google Play و Apple App Store في `DEPLOYMENT_GUIDE.md`.

- [x] **المرحلة 6: الطابع الرسمي والتنظيم الأكاديمي الشامل (Official Academic Overhaul)**
  - [x] **المهمة 6.1**: تحرير قيود كلمة المرور ورمز الدخول (السماح بأي رمز حر وليس 6 أرقام فقط).
  - [x] **المهمة 6.2**: إزالة كافة الستيكرات والإيموجيات والنصوص الاستعراضية، وتحويل الواجهات إلى أسلوب رسمي وموجز.
  - [x] **المهمة 6.3**: تقييد إشراف ونشر الممثلين على مجموعاتهم ومراحلهم الدراسية فقط (Representative Scoped Permissions).
  - [x] **المهمة 6.4**: بناء وتكامل "خانات المقررات الدراسية" (Subject Hubs) لتشمل محاضرات وتبليغات كل مادة بدقة وتكامل.
  - [x] **المهمة 6.5**: الاختبارات والتحقق الشامل (Tests & Web Release Build) وضمان جاهزية النظام 100%.
