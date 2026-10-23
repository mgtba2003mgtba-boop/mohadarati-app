import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class NativePdfService {
  static final NativePdfService instance = NativePdfService._internal();
  factory NativePdfService() => instance;
  NativePdfService._internal();

  static const MethodChannel _channel = MethodChannel('iq.edu.nust.mohadarati/pdf');

  bool get isSupported => !kIsWeb && Platform.isAndroid;

  /// فتح ملف PDF واستخراج عدد الصفحات
  Future<int> openPdf(String filePath) async {
    if (!isSupported) return 0;
    try {
      final res = await _channel.invokeMapMethod<String, dynamic>('openPdf', {
        'filePath': filePath,
      });
      return (res?['pageCount'] as int?) ?? 0;
    } catch (e) {
      debugPrint('[-] NativePdfService openPdf error: $e');
      return 0;
    }
  }

  /// تصيير صفحة محددة كصورة عالية الدقة للرسم المباشر
  Future<Uint8List?> renderPage(int pageIndex, {int targetWidth = 1080}) async {
    if (!isSupported) return null;
    try {
      final bytes = await _channel.invokeMethod<Uint8List>('renderPage', {
        'pageIndex': pageIndex,
        'targetWidth': targetWidth,
      });
      return bytes;
    } catch (e) {
      debugPrint('[-] NativePdfService renderPage error ($pageIndex): $e');
      return null;
    }
  }

  /// إغلاق الملف وتحرير الموارد في الذاكرة
  Future<void> closePdf() async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod('closePdf');
    } catch (_) {}
  }
}
