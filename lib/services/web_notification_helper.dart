import 'web_notification_helper_stub.dart'
    if (dart.library.html) 'web_notification_helper_web.dart' as impl;

/// طلب إذن الإشعارات من المتصفح / النظام
Future<bool> requestWebNotificationPermission() =>
    impl.requestWebNotificationPermission();

/// الحصول على حالة صلاحية الإشعارات
String getWebNotificationPermissionStatus() =>
    impl.getWebNotificationPermissionStatus();

/// فحص هل إشعارات الجهاز مفعلة وممنوحة
Future<bool> areDeviceNotificationsEnabled() =>
    impl.areDeviceNotificationsEnabled();

/// إرسال إشعار نظام حقيقي متعدد المنصات
void showWebNotification({
  required String title,
  required String body,
  String? tag,
  String? url,
}) =>
    impl.showWebNotification(
      title: title,
      body: body,
      tag: tag,
      url: url,
    );
