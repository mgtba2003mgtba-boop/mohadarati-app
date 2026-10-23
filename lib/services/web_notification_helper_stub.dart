import 'dart:io' show Platform;
import 'package:flutter/services.dart';

const MethodChannel _channel = MethodChannel('iq.edu.nust.mohadarati/notifications');

/// طلب إذن الإشعارات من نظام أندرويد 13 فما فوق
Future<bool> requestWebNotificationPermission() async {
  try {
    if (Platform.isAndroid) {
      final res = await _channel.invokeMethod<bool>('requestPermission');
      return res ?? false;
    }
  } catch (_) {}
  return false;
}

/// فحص حالة إذن الإشعارات في النظام
String getWebNotificationPermissionStatus() {
  return 'default';
}

/// فحص دقيق لحالة الإشعارات في نظام أندرويد
Future<bool> areDeviceNotificationsEnabled() async {
  try {
    if (Platform.isAndroid) {
      final res = await _channel.invokeMethod<bool>('areNotificationsEnabled');
      return res ?? true;
    }
  } catch (_) {}
  return true;
}

/// إرسال إشعار نظام حقيقي على شريط الحالة وشاشة القفل للأندرويد
void showWebNotification({
  required String title,
  required String body,
  String? tag,
  String? url,
}) {
  try {
    if (Platform.isAndroid) {
      _channel.invokeMethod('showNotification', {
        'title': title,
        'body': body,
        'tag': tag ?? 'nust_${DateTime.now().millisecondsSinceEpoch}',
        'url': url,
      });
    }
  } catch (_) {}
}
