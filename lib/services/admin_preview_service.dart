import 'package:flutter/foundation.dart';
import '../models/app_user_model.dart';
import '../core/constants/app_constants.dart';

/// ── خدمة وسياق المعاينة الفورية للآدمن (Admin Live Preview Context) ─────────
/// تتيح للمشرف العام (مجتبى عواد) التبديل السريع بنقرة واحدة بين أي قسم ومرحلة وشعبة،
/// وتحديث كافة شاشات التطبيق (الرئيسية، المقررات، الجدول) لتعرض بدقة ما يراه طالب تلك الشعبة.
class AdminPreviewService extends ChangeNotifier {
  static final AdminPreviewService _instance = AdminPreviewService._internal();
  factory AdminPreviewService() => _instance;
  AdminPreviewService._internal();

  String _department = AppConstants.departments.first;
  String _stage = AppConstants.stages.first;
  String? _section = 'A';
  bool _isCustomActive = false;

  String get department => _department;
  String get stage => _stage;
  String? get section => _section;
  bool get isCustomActive => _isCustomActive;

  /// تهيئة السياق عند تسجيل الدخول
  void initialize(AppUserModel? user) {
    if (user != null && !_isCustomActive) {
      _department = user.department.isNotEmpty ? user.department : AppConstants.departments.first;
      _stage = user.stage.isNotEmpty ? user.stage : AppConstants.stages.first;
      _section = (user.section != null && user.section!.isNotEmpty) ? user.section : 'A';
    }
  }

  /// تغيير القسم
  void setDepartment(String dept) {
    if (_department != dept) {
      _department = dept;
      _isCustomActive = true;
      notifyListeners();
    }
  }

  /// تغيير المرحلة
  void setStage(String stage) {
    if (_stage != stage) {
      _stage = stage;
      _isCustomActive = true;
      notifyListeners();
    }
  }

  /// تغيير الشعبة (مثلاً 'A', 'B', 'C', 'D' أو null للكل)
  void setSection(String? section) {
    final clean = (section == null || section == 'ALL' || section.isEmpty) ? null : section;
    if (_section != clean) {
      _section = clean;
      _isCustomActive = true;
      notifyListeners();
    }
  }

  /// تبديل كامل (قسم + مرحلة + شعبة) دفعة واحدة
  void setTarget({required String department, required String stage, String? section}) {
    _department = department;
    _stage = stage;
    _section = (section == null || section == 'ALL' || section.isEmpty) ? null : section;
    _isCustomActive = true;
    notifyListeners();
  }

  /// إعادة تعيين الوضع الافتراضي لبيانات المشرف الشخصية
  void reset(AppUserModel? user) {
    _isCustomActive = false;
    if (user != null) {
      _department = user.department.isNotEmpty ? user.department : AppConstants.departments.first;
      _stage = user.stage.isNotEmpty ? user.stage : AppConstants.stages.first;
      _section = (user.section != null && user.section!.isNotEmpty) ? user.section : 'A';
    } else {
      _department = AppConstants.departments.first;
      _stage = AppConstants.stages.first;
      _section = 'A';
    }
    notifyListeners();
  }
}
