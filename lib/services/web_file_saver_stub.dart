import 'dart:io' show Platform;
import 'dart:typed_data';
import 'package:flutter/services.dart';

const MethodChannel _updaterChannel = MethodChannel('iq.edu.nust.mohadarati/updater');

/// حفظ الملف مباشرة في مجلد التنزيلات بالجهاز (Android Downloads/محاضراتي) دون فتح متصفح
Future<bool> saveFileInBrowser(Uint8List bytes, String fileName) async {
  try {
    if (Platform.isAndroid) {
      final res = await _updaterChannel.invokeMethod<bool>('saveToDownloads', {
        'bytes': bytes,
        'fileName': fileName,
      });
      return res ?? false;
    }
  } catch (_) {}
  return false;
}

String? createBlobUrl(Uint8List bytes, [String? mimeType]) => null;

void revokeBlobUrl(String url) {}
