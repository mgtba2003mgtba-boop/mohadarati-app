import 'dart:async';
import 'dart:typed_data';

/// تنفيذ وهمي آمن لبيئة الويب بدون أي استيراد لـ dart:io
class LocalDocumentCacheService {
  static String computeStableKey({
    required String lectureId,
    String? fileName,
    String? url,
  }) {
    final cleanId = lectureId.trim();
    if (cleanId.isNotEmpty) return 'doc_id_$cleanId';
    final cleanName = (fileName ?? '').trim();
    if (cleanName.isNotEmpty) {
      final sanitized = cleanName.replaceAll(RegExp(r'[^\w\.\-]'), '_');
      return 'doc_name_$sanitized';
    }
    final hash = (url ?? '').hashCode.abs();
    return 'doc_hash_$hash';
  }

  static Future<String?> getCacheDirPath() async => null;

  static Future<String?> findExistingDocumentPath({
    required String lectureId,
    String? fileName,
    String? title,
    String? url,
  }) async => null;

  static Future<Uint8List?> getCachedDocumentBytes({
    required String lectureId,
    String? fileName,
    String? title,
    String? url,
  }) async => null;

  static Future<String?> saveDocumentToCache({
    required String lectureId,
    String? fileName,
    String? url,
    required List<int> bytes,
  }) async => null;
}
