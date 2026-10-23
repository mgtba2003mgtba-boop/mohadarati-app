import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'lecture_ux_service.dart';

/// محرك التخزين المؤقت المحلي للمستندات والـ PDFs لأنظمة أندرويد و iOS (Local-First Offline)
class LocalDocumentCacheService {
  static const MethodChannel _updaterChannel = MethodChannel('iq.edu.nust.mohadarati/updater');

  static String computeStableKey({
    required String lectureId,
    String? fileName,
    String? url,
  }) {
    final cleanId = lectureId.trim();
    if (cleanId.isNotEmpty) {
      return 'doc_id_$cleanId';
    }
    final cleanName = (fileName ?? '').trim();
    if (cleanName.isNotEmpty) {
      final sanitized = cleanName.replaceAll(RegExp(r'[^\w\.\-]'), '_');
      return 'doc_name_$sanitized';
    }
    final hash = (url ?? '').hashCode.abs();
    return 'doc_hash_$hash';
  }

  static Future<String?> getCacheDirPath() async {
    try {
      final res = await _updaterChannel.invokeMethod<String>('getCacheDir');
      return res;
    } catch (_) {
      return null;
    }
  }

  static Future<String?> findExistingDocumentPath({
    required String lectureId,
    String? fileName,
    String? title,
    String? url,
  }) async {
    try {
      final cacheDirStr = await getCacheDirPath();
      final String cachePath = cacheDirStr ?? Directory.systemTemp.path;

      final stableKey = computeStableKey(lectureId: lectureId, fileName: fileName, url: url);
      final primaryFile = File('$cachePath/$stableKey.pdf');

      if (await primaryFile.exists() && (await primaryFile.length()) > 1024) {
        return primaryFile.path;
      }

      if (url != null && url.isNotEmpty) {
        final legacyFile = File('$cachePath/doc_${url.hashCode.abs()}.pdf');
        if (await legacyFile.exists() && (await legacyFile.length()) > 1024) {
          return legacyFile.path;
        }
      }

      // فحص مجلد التنزيلات الخارجي (Downloads/محاضراتي)
      final candidateNames = [
        if (fileName != null && fileName.isNotEmpty) fileName,
        if (title != null && title.isNotEmpty) '$title.pdf',
        if (title != null && title.isNotEmpty) title,
      ];

      for (final name in candidateNames) {
        final cleanName = name.endsWith('.pdf') ? name : '$name.pdf';
        final dlFile = File('/storage/emulated/0/Download/محاضراتي/$cleanName');
        try {
          if (await dlFile.exists() && (await dlFile.length()) > 1024) {
            return dlFile.path;
          }
        } catch (_) {}
      }
    } catch (e) {
      debugPrint('[-] findExistingDocumentPath error: $e');
    }
    return null;
  }

  static Future<Uint8List?> getCachedDocumentBytes({
    required String lectureId,
    String? fileName,
    String? title,
    String? url,
  }) async {
    final path = await findExistingDocumentPath(
      lectureId: lectureId,
      fileName: fileName,
      title: title,
      url: url,
    );
    if (path != null) {
      try {
        final file = File(path);
        final bytes = await file.readAsBytes();
        if (bytes.isNotEmpty) {
          if (lectureId.isNotEmpty) {
            LectureUxService.instance.markLectureCached(lectureId);
          }
          return Uint8List.fromList(bytes);
        }
      } catch (e) {
        debugPrint('[-] getCachedDocumentBytes read error: $e');
      }
    }
    return null;
  }

  static Future<String?> saveDocumentToCache({
    required String lectureId,
    String? fileName,
    String? url,
    required List<int> bytes,
  }) async {
    if (bytes.isEmpty) return null;
    try {
      final cacheDirStr = await getCacheDirPath();
      final String cachePath = cacheDirStr ?? Directory.systemTemp.path;
      final stableKey = computeStableKey(lectureId: lectureId, fileName: fileName, url: url);
      final targetFile = File('$cachePath/$stableKey.pdf');

      await targetFile.writeAsBytes(bytes);
      if (lectureId.isNotEmpty) {
        LectureUxService.instance.markLectureCached(lectureId);
      }
      return targetFile.path;
    } catch (e) {
      debugPrint('[-] saveDocumentToCache error: $e');
      return null;
    }
  }
}
