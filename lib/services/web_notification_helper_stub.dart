/// بديل لمنصات غير الويب لتجنب أخطاء الاستيراد أثناء البناء والاختبارات البرمجية
Future<bool> requestWebNotificationPermission() async => false;

String getWebNotificationPermissionStatus() => 'unsupported';

void showWebNotification({
  required String title,
  required String body,
  String? tag,
  String? url,
}) {}
