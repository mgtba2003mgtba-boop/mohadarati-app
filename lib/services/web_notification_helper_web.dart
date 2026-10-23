// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
// ignore: avoid_web_libraries_in_flutter
import 'dart:js' as js;

/// طلب إذن الإشعارات من متصفح الآيفون أو الأندرويد في بيئة الويب PWA
Future<bool> requestWebNotificationPermission() async {
  try {
    if (js.context.hasProperty('requestAppNotificationPermission')) {
      final res = await js.context.callMethod('requestAppNotificationPermission');
      return res == true;
    } else if (html.Notification.supported) {
      final perm = await html.Notification.requestPermission();
      return perm == 'granted';
    }
  } catch (_) {}
  return false;
}

/// فحص حالة إذن الإشعارات في المتصفح
String getWebNotificationPermissionStatus() {
  try {
    if (js.context.hasProperty('getNotificationPermissionStatus')) {
      return js.context.callMethod('getNotificationPermissionStatus')?.toString() ?? 'unsupported';
    } else if (html.Notification.supported) {
      return html.Notification.permission ?? 'default';
    }
  } catch (_) {}
  return 'unsupported';
}

/// فحص دقيق هل الإشعارات مقبولة ومفعلة في المتصفح
Future<bool> areDeviceNotificationsEnabled() async {
  try {
    if (html.Notification.supported) {
      return html.Notification.permission == 'granted';
    }
  } catch (_) {}
  return false;
}

/// إرسال إشعار نظام حقيقي على شاشة القفل ومركز الإشعارات في الهاتف
void showWebNotification({
  required String title,
  required String body,
  String? tag,
  String? url,
}) {
  try {
    if (js.context.hasProperty('showNativeNotification')) {
      js.context.callMethod('showNativeNotification', [title, body, tag, url]);
    } else if (html.Notification.supported && html.Notification.permission == 'granted') {
      html.Notification(
        title,
        body: body,
        icon: '/icons/Icon-192.png',
        tag: tag ?? 'nust_${DateTime.now().millisecondsSinceEpoch}',
      );
    }
  } catch (_) {}
}
