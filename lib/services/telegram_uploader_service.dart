import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:file_picker/file_picker.dart';
import '../core/constants/app_constants.dart';
import '../models/lecture_model.dart';
import 'supabase_service.dart';
import 'web_uploader.dart';
import 'web_file_saver.dart';

/// نتيجة عملية رفع المحاضرة
class UploadLectureResult {
  final bool success;
  final String message;
  final int? telegramMessageId;
  final String? fileId;
  final String? fileName;
  final int? fileSizeBytes;

  UploadLectureResult({
    required this.success,
    required this.message,
    this.telegramMessageId,
    this.fileId,
    this.fileName,
    this.fileSizeBytes,
  });
}

/// نتيجة عملية رفع أي ملف أو صورة إلى سحابة تيليجرام
class UploadGeneralFileResult {
  final bool success;
  final String message;
  final int? telegramMessageId;
  final String? fileUrl;
  final String? fileName;
  final int? fileSizeBytes;
  final String? mimeType;

  UploadGeneralFileResult({
    required this.success,
    required this.message,
    this.telegramMessageId,
    this.fileUrl,
    this.fileName,
    this.fileSizeBytes,
    this.mimeType,
  });
}

class TelegramUploaderService {
  static final TelegramUploaderService _instance = TelegramUploaderService._internal();
  factory TelegramUploaderService() => _instance;
  TelegramUploaderService._internal();

  /// اختيار ملف أو ملفات متعددة للمحاضرة من ذاكرة الجهاز دون تقييد بالحجم أو العدد
  Future<List<PlatformFile>> pickLectureFiles({bool allowAny = false}) async {
    final extensions = [
      'pdf', 'docx', 'doc', 'pptx', 'ppt', 'png', 'jpg', 'jpeg', 'webp', 'zip',
      'mp4', 'mkv', 'avi', 'mov', 'webm', 'rar', '7z',
      'PDF', 'DOCX', 'DOC', 'PPTX', 'PPT', 'PNG', 'JPG', 'JPEG', 'WEBP', 'ZIP',
      'MP4', 'MKV', 'AVI', 'MOV', 'WEBM', 'RAR', '7Z',
    ];

    if (allowAny) {
      try {
        final List<PlatformFile> files = await FilePicker.pickFiles(
          type: FileType.any,
        );
        return files;
      } catch (e) {
        debugPrint('[-] FilePicker (any) error: $e');
        return [];
      }
    }

    try {
      final List<PlatformFile> files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: extensions,
      );
      return files;
    } catch (e) {
      debugPrint('[-] FilePicker custom error: $e - falling back to FileType.any');
      try {
        final List<PlatformFile> fallback = await FilePicker.pickFiles(
          type: FileType.any,
        );
        return fallback;
      } catch (e2) {
        debugPrint('[-] FilePicker fallback error: $e2');
        return [];
      }
    }
  }

  /// للتوافق مع الواجهات القديمة: اختيار ملف فردي واحد
  Future<PlatformFile?> pickLectureFile({bool allowAny = false}) async {
    final list = await pickLectureFiles(allowAny: allowAny);
    return list.isNotEmpty ? list.first : null;
  }

  /// اختيار صورة أو ملف PDF (للجداول الأسبوعية وجداول الامتحانات والبوسترات)
  Future<PlatformFile?> pickImageOrPdfFile() async {
    try {
      final List<PlatformFile> files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: [
          'png', 'jpg', 'jpeg', 'webp', 'pdf',
          'PNG', 'JPG', 'JPEG', 'WEBP', 'PDF',
        ],
      );

      if (files.isNotEmpty) {
        return files.first;
      }
      return null;
    } catch (e) {
      debugPrint('[-] FilePicker error: $e - attempting fallback');
      try {
        final List<PlatformFile> fallback = await FilePicker.pickFiles(type: FileType.any);
        return fallback.isNotEmpty ? fallback.first : null;
      } catch (_) {
        return null;
      }
    }
  }

  /// اختيار صورة فقط من المعرض / الستوديو (لبنل البوسترات والإعلانات المصورة)
  /// يوجّه النظام مباشرة إلى تطبيق الستوديو (Photo Gallery) على أندرويد وiOS والويب
  Future<PlatformFile?> pickImageOnly() async {
    try {
      final List<PlatformFile> files = await FilePicker.pickFiles(
        type: FileType.image,
      );

      if (files.isNotEmpty) {
        return files.first;
      }
      return null;
    } catch (e) {
      debugPrint('[-] FilePicker (image) error: $e - attempting custom fallback');
      try {
        final List<PlatformFile> fallback = await FilePicker.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['png', 'jpg', 'jpeg', 'webp', 'PNG', 'JPG', 'JPEG', 'WEBP'],
        );
        return fallback.isNotEmpty ? fallback.first : null;
      } catch (e2) {
        debugPrint('[-] FilePicker fallback error: $e2');
        return null;
      }
    }
  }

  /// قراءة بايتات الملف بأمان عبر مختلف المنصات (Web و Desktop و Mobile)
  Future<Uint8List> _getFileBytes(PlatformFile file) async {
    return await file.readAsBytes();
  }

  /// حساب حجم الملف بالبايت
  Future<int> getFileSize(PlatformFile file) async {
    final syncLen = file.lengthSync();
    if (syncLen != null && syncLen > 0) {
      return syncLen;
    }
    try {
      final len = await file.length();
      if (len != null) return len;
    } catch (_) {}
    return 0;
  }

  /// تنسيق حجم الملف للعرض البشري
  String _formatBytes(int bytes) {
    if (bytes >= 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} غيغابايت';
    } else if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} ميغابايت';
    } else if (bytes >= 1024) {
      return '${(bytes / 1024).toStringAsFixed(0)} كيلوبايت';
    } else {
      return '$bytes بايت';
    }
  }

  /// إرسال مستند إلى تيليجرام مع إعادة المحاولة التلقائية عند تذبذب الاتصال وتتبع حي لتدفق البايتات
  Future<http.Response?> _sendDocumentWithRetry({
    required Uri uri,
    required String chatId,
    required String caption,
    required Uint8List fileBytes,
    required String fileName,
    int maxAttempts = 3,
    void Function(String status, double? progress)? onProgress,
    void Function(int bytesSent, int totalBytes, double ratio)? onBytesProgress,
  }) async {
    http.Response? lastResponse;
    dynamic lastError;

    for (int attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        if (attempt > 1) {
          onProgress?.call('تذبذب في شبكة الاتصال، إعادة المحاولة تلقائياً ($attempt/$maxAttempts)...', 0.4);
          debugPrint('[~] Retrying Telegram upload attempt $attempt of $maxAttempts after backoff...');
          await Future.delayed(Duration(seconds: (attempt - 1) * 2));
        }

        final response = await postMultipartWithProgress(
          uri: uri,
          fields: {
            'chat_id': chatId,
            'caption': caption,
          },
          fileBytes: fileBytes,
          fileField: 'document',
          fileName: fileName,
          onProgress: (sent, total) {
            final ratio = total > 0 ? (sent / total).clamp(0.0, 1.0) : 0.0;
            onBytesProgress?.call(sent, total, ratio);
          },
          timeout: const Duration(minutes: 30),
        );

        lastResponse = response;

        if (response.statusCode == 200) {
          return response;
        }

        // أخطاء غير قابلة للإعادة (مثل توكن غير صحيح أو خطأ صلاحيات)
        if (response.statusCode == 400 || response.statusCode == 401 || response.statusCode == 403 || response.statusCode == 404) {
          debugPrint('[-] Telegram non-retryable response (${response.statusCode}): ${response.body}');
          return response;
        }

        debugPrint('[-] Telegram returned status ${response.statusCode} on attempt $attempt, retrying...');
      } catch (err) {
        lastError = err;
        debugPrint('[-] Telegram socket/network exception on attempt $attempt: $err');
        if (attempt == maxAttempts) {
          rethrow;
        }
      }
    }

    if (lastResponse != null) return lastResponse;
    if (lastError != null) throw lastError;
    return null;
  }

  /// جلب رابط مباشر جديد للملف في حال الحاجة لتحديث الرابط (مع دعم البروكسي لتجاوز CORS)
  Future<String?> resolveFileUrl(String fileId) async {
    try {
      if (kIsWeb) {
        return AppConstants.resolveImageUrl('/api/proxy?file_id=$fileId');
      }

      final botToken = AppConstants.lecturesBotToken;
      final uri = Uri.parse('https://api.telegram.org/bot$botToken/getFile?file_id=$fileId');
      final res = await http.get(uri).timeout(const Duration(seconds: 15));
      if (res.statusCode == 200) {
        final data = jsonDecode(utf8.decode(res.bodyBytes));
        final path = data['result']?['file_path'];
        if (path != null) {
          return 'https://api.telegram.org/file/bot$botToken/$path';
        }
      }
    } catch (e) {
      debugPrint('[-] Error resolving file URL: $e');
    }
    return AppConstants.resolveImageUrl('/api/proxy?file_id=$fileId');
  }

  /// كشف نوع الوسائط (MIME Type) من اسم الملف
  String _detectMimeType(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.pdf')) return 'application/pdf';
    if (lower.endsWith('.mp4')) return 'video/mp4';
    if (lower.endsWith('.mkv')) return 'video/x-matroska';
    if (lower.endsWith('.avi')) return 'video/x-msvideo';
    if (lower.endsWith('.mov')) return 'video/quicktime';
    if (lower.endsWith('.webm')) return 'video/webm';
    if (lower.endsWith('.doc')) return 'application/msword';
    if (lower.endsWith('.docx')) {
      return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
    }
    if (lower.endsWith('.ppt')) return 'application/vnd.ms-powerpoint';
    if (lower.endsWith('.pptx')) {
      return 'application/vnd.openxmlformats-officedocument.presentationml.presentation';
    }
    if (lower.endsWith('.zip')) return 'application/zip';
    if (lower.endsWith('.rar')) return 'application/x-rar-compressed';
    if (lower.endsWith('.7z')) return 'application/x-7z-compressed';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    return 'application/octet-stream';
  }

  /// تنزيل وتجميع أجزاء المحاضرة المقسمة سحابياً وإعادتها كملف أصلي كامل واحد
  Future<Uint8List?> downloadChunkedLectureParts({
    required String partsDescriptor,
    void Function(String status, double progress)? onProgress,
  }) async {
    try {
      if (!partsDescriptor.startsWith('telegram:parts:')) return null;
      final jsonStr = partsDescriptor.replaceFirst('telegram:parts:', '');
      final dynamic decoded = jsonDecode(jsonStr);
      if (decoded is! List) return null;

      final List<Map<String, dynamic>> parts =
          List<Map<String, dynamic>>.from(decoded);
      if (parts.isEmpty) return null;

      final totalParts = parts.length;
      final BytesBuilder fullBuilder = BytesBuilder(copy: false);

      for (int i = 0; i < totalParts; i++) {
        final part = parts[i];
        final fileId = part['file_id']?.toString();
        final partNum = part['part'] ?? (i + 1);

        if (fileId == null || fileId.isEmpty) {
          throw Exception('معرف الجزء رقم $partNum مفقود');
        }

        final partProgress = i / totalParts;
        onProgress?.call(
          'جاري التحميل...',
          partProgress,
        );

        // استخدام رابط البروكسي المباشر لتجاوز CORS وحجب الشبكات في المتصفحات
        final fileUrl = kIsWeb
            ? AppConstants.resolveImageUrl('/api/proxy?file_id=$fileId')
            : (await resolveFileUrl(fileId) ?? AppConstants.resolveImageUrl('/api/proxy?file_id=$fileId'));

        if (fileUrl.isEmpty) {
          throw Exception('تعذر استخراج رابط تحميل الجزء رقم $partNum');
        }

        http.Response? partRes;
        dynamic lastErr;
        for (int attempt = 1; attempt <= 3; attempt++) {
          try {
            final res = await http
                .get(Uri.parse(fileUrl))
                .timeout(const Duration(minutes: 5));
            if (res.statusCode == 200 && res.bodyBytes.isNotEmpty) {
              partRes = res;
              break;
            }
          } catch (e) {
            lastErr = e;
            debugPrint('[-] Part $partNum download attempt $attempt error: $e');
            await Future.delayed(Duration(seconds: attempt));
          }
        }

        if (partRes == null || partRes.statusCode != 200) {
          throw Exception('فشل تنزيل الجزء $partNum (${partRes?.statusCode ?? lastErr ?? 'timeout'})');
        }

        fullBuilder.add(partRes.bodyBytes);
        final ratio = (i + 1) / totalParts;
        onProgress?.call('جاري التحميل...', ratio);
      }

      onProgress?.call('تم التحميل', 1.0);
      return fullBuilder.takeBytes();
    } catch (e) {
      debugPrint('[-] Error downloading chunked lecture parts: $e');
      rethrow;
    }
  }

  /// رفع أي ملف أو صورة مباشرة إلى سحابة تيليجرام (للجداول والبوسترات) مع مؤشر تقدم حي
  Future<UploadGeneralFileResult> uploadFileToTelegram({
    required PlatformFile file,
    Uint8List? overrideBytes,
    String? overrideFileName,
    String? caption,
    String fileType = 'general', // 'schedule' أو 'banner' أو 'general'
    void Function(String status, double? progress)? onProgress,
    void Function(int bytesSent, int totalBytes, double progress, String status)? onDetailedProgress,
  }) async {
    try {
      onProgress?.call('جاري الرفع...', 0.1);
      final Uint8List fileBytes = overrideBytes ?? await _getFileBytes(file);
      final String finalFileName = overrideFileName ?? file.name;
      if (fileBytes.isEmpty) {
        return UploadGeneralFileResult(
          success: false,
          message: 'تعذر قراءة بيانات الملف.',
        );
      }

      // دعم الملفات الكبيرة حتى 2 غيغابايت دون تقييد
      if (fileBytes.length > 2048 * 1024 * 1024) {
        return UploadGeneralFileResult(
          success: false,
          message: 'حجم الملف يتجاوز الحد الأقصى (2 غيغابايت).',
        );
      }

      final tag = fileType == 'schedule'
          ? '📅 جدول دراسي/امتحاني'
          : fileType == 'banner'
              ? '📢 إعلان جامعي'
              : fileType == 'announcement'
                  ? '📣 تبليغ أكاديمي رسمي'
                  : '📁 ملف جامعي';
      final fullCaption = caption != null && caption.trim().isNotEmpty
          ? '$tag\n${caption.trim()}'
          : tag;

      final botToken = AppConstants.lecturesBotToken;
      final channelId = AppConstants.lecturesChannelId;
      final uri = Uri.parse('https://api.telegram.org/bot$botToken/sendDocument');

      final response = await _sendDocumentWithRetry(
        uri: uri,
        chatId: channelId.toString(),
        caption: fullCaption,
        fileBytes: fileBytes,
        fileName: finalFileName,
        maxAttempts: 3,
        onProgress: onProgress,
        onBytesProgress: (sent, total, ratio) {
          final mappedProg = (ratio * 0.85).clamp(0.1, 0.85);
          const status = 'جاري الرفع...';
          onProgress?.call(status, mappedProg);
          onDetailedProgress?.call(sent, total, mappedProg, status);
        },
      );

      if (response != null && response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        if (data['ok'] == true && data['result'] != null) {
          final result = data['result'];
          final msgId = result['message_id'] as int?;
          final doc = result['document'];
          String? fileId = doc?['file_id']?.toString();
          String mimeType = doc?['mime_type']?.toString() ?? 'application/octet-stream';

          if (fileId == null) {
            if (result['photo'] is List && (result['photo'] as List).isNotEmpty) {
              fileId = (result['photo'] as List).last['file_id']?.toString();
              mimeType = 'image/jpeg';
            } else if (result['sticker'] != null) {
              fileId = result['sticker']['file_id']?.toString();
              mimeType = 'image/webp';
            } else if (result['video'] != null) {
              fileId = result['video']['file_id']?.toString();
              mimeType = result['video']['mime_type']?.toString() ?? 'video/mp4';
            } else if (result['animation'] != null) {
              fileId = result['animation']['file_id']?.toString();
              mimeType = result['animation']['mime_type']?.toString() ?? 'video/mp4';
            }
          }

          // جلب مسار التحميل المباشر السحابي
          String? directUrl;
          if (fileId != null) {
            try {
              final getFileUri = Uri.parse('https://api.telegram.org/bot$botToken/getFile?file_id=$fileId');
              final getFileRes = await http.get(getFileUri).timeout(const Duration(seconds: 15));
              if (getFileRes.statusCode == 200) {
                final getFileData = jsonDecode(utf8.decode(getFileRes.bodyBytes));
                final filePath = getFileData['result']?['file_path'];
                if (filePath != null) {
                  directUrl = 'https://api.telegram.org/file/bot$botToken/$filePath';
                }
              }
            } catch (e) {
              debugPrint('[-] Error getting file path: $e');
            }
          }

          directUrl ??= '';

          onProgress?.call('تم الرفع', 1.0);

          return UploadGeneralFileResult(
            success: true,
            message: 'تم الرفع بنجاح',
            telegramMessageId: msgId,
            fileUrl: directUrl,
            fileName: file.name,
            fileSizeBytes: fileBytes.length,
            mimeType: mimeType,
          );
        }
      }

      final statusCode = response?.statusCode ?? 500;
      final body = response?.body ?? '';
      String friendlyMessage = 'فشل الرفع ($statusCode)';
      if (statusCode == 400 && body.contains('file is too big')) {
        friendlyMessage = 'حجم الملف يتجاوز الحد المسموح به (50 ميغابايت).';
      } else if (body.isNotEmpty) {
        friendlyMessage = '$friendlyMessage: $body';
      }

      return UploadGeneralFileResult(
        success: false,
        message: friendlyMessage,
      );
    } catch (e) {
      debugPrint('[-] Telegram cloud general file upload error: $e');
      return UploadGeneralFileResult(
        success: false,
        message: 'انقطع الاتصال أثناء الرفع. يرجى إعادة المحاولة.',
      );
    }
  }

  /// حذف رسالة أو منشور من قناة تيليجرام المرتبطة
  Future<bool> deleteMessageFromTelegram({
    required int messageId,
    int? channelId,
  }) async {
    try {
      final botToken = AppConstants.lecturesBotToken;
      final targetChannel = channelId ?? AppConstants.lecturesChannelId;

      // 1. المحاولة عبر POST request
      final uri = Uri.parse('https://api.telegram.org/bot$botToken/deleteMessage');
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'chat_id': targetChannel,
          'message_id': messageId,
        }),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        if (data['ok'] == true) {
          debugPrint('[+] Deleted message $messageId from Telegram channel $targetChannel');
          return true;
        }
      }

      // 2. المحاولة البديلة عبر GET مع معلمات الاستعلام
      final getUri = Uri.parse(
        'https://api.telegram.org/bot$botToken/deleteMessage?chat_id=$targetChannel&message_id=$messageId',
      );
      final getRes = await http.get(getUri).timeout(const Duration(seconds: 10));
      if (getRes.statusCode == 200) {
        final getData = jsonDecode(utf8.decode(getRes.bodyBytes));
        if (getData['ok'] == true) {
          debugPrint('[+] Deleted message $messageId from Telegram via GET fallback');
          return true;
        }
      }

      debugPrint('[-] Note: Telegram deleteMessage responded with: ${response.statusCode} - ${response.body}');
      return false;
    } catch (e) {
      debugPrint('[-] Note: Error attempting to delete message from Telegram: $e');
      return false;
    }
  }

  /// رفع المحاضرة الكبيرة جداً عبر سيرفر البث التابع للمنظومة (Telethon MTProto يدعم حتى 2000MB بدون تقييد)
  Future<UploadLectureResult?> _uploadViaStreamer({
    required Uint8List fileBytes,
    required String fileName,
    required String title,
    required String subjectName,
    required String department,
    required String stage,
    required String section,
    required int semester,
    required String lectureType,
    String? description,
    required String uploaderId,
    required String uploaderName,
    required String uploaderRole,
    void Function(String status, double? progress)? onProgress,
  }) async {
    try {
      final streamerUrl = '${AppConstants.telegramStreamerBaseUrl}/api/upload-lecture';
      final uri = Uri.parse(streamerUrl);

      final request = http.MultipartRequest('POST', uri);
      request.fields['title'] = title.trim();
      request.fields['subject_name'] = subjectName.trim();
      request.fields['department'] = department;
      request.fields['stage'] = stage;
      request.fields['section'] = section;
      request.fields['semester'] = semester.toString();
      request.fields['lecture_type'] = lectureType;
      if (description != null && description.trim().isNotEmpty) {
        request.fields['description'] = description.trim();
      }
      request.fields['uploader_id'] = uploaderId;
      request.fields['uploader_name'] = uploaderName;
      request.fields['uploader_role'] = uploaderRole;

      request.files.add(
        http.MultipartFile.fromBytes(
          'file',
          fileBytes,
          filename: fileName,
        ),
      );

      onProgress?.call('جاري الرفع...', 0.4);

      final streamedResponse = await request.send().timeout(const Duration(minutes: 30));
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        if (data['ok'] == true || data['success'] == true) {
          final msgId = data['telegram_message_id'] as int?;
          final fileId = data['file_id']?.toString();
          return UploadLectureResult(
            success: true,
            telegramMessageId: msgId,
            fileId: fileId,
            fileName: fileName,
            fileSizeBytes: fileBytes.length,
            message: 'تم الرفع بنجاح',
          );
        }
      }
    } catch (e) {
      debugPrint('[-] Streamer upload attempt failed: $e');
    }
    return null;
  }

  /// رفع ملف المحاضرة والميتا داتا مباشرة إلى سحابة تيليجرام وقاعدة بيانات سوبابيز
  /// يدعم تتبع تدفق البايتات لحظياً والتقسيم التلقائي للأحجام الكبيرة (> 19MB حتى 2GB) دون الاصطدام بحدود تيليجرام
  Future<UploadLectureResult> uploadLecture({
    required PlatformFile file,
    required String title,
    required String subjectName,
    required String department,
    required String stage,
    String section = 'ALL',
    required int semester,
    required String lectureType,
    String? professorName,
    String? description,
    required String uploaderId,
    required String uploaderName,
    required String uploaderRole,
    void Function(String status, double? progress)? onProgress,
    void Function(int bytesSent, int totalBytes, double progress, String status)? onDetailedProgress,
  }) async {
    try {
      onProgress?.call('جاري الرفع...', 0.05);
      final Uint8List fileBytes = await _getFileBytes(file);
      final totalBytes = fileBytes.length;
      if (fileBytes.isEmpty) {
        return UploadLectureResult(
          success: false,
          message: 'تعذر قراءة بيانات الملف. يرجى إعادة اختيار الملف.',
        );
      }

      // الحد الأقصى المسموح به عالمياً في سحابة تيليجرام (2048 ميغابايت / 2GB)
      if (totalBytes > 2048 * 1024 * 1024) {
        return UploadLectureResult(
          success: false,
          message: 'حجم الملف يتجاوز الحد الأقصى المسموح به (2 غيغابايت).',
        );
      }

      final botToken = AppConstants.lecturesBotToken;
      final channelId = AppConstants.lecturesChannelId;
      final uri = Uri.parse('https://api.telegram.org/bot$botToken/sendDocument');
      final realMime = _detectMimeType(file.name);

      // إذا كان الملف أكبر من 19MB، نحاول أولاً رفعه عبر خادم البث وMTProto إن كان متاحاً
      if (totalBytes > 19 * 1024 * 1024) {
        final streamerRes = await _uploadViaStreamer(
          fileBytes: fileBytes,
          fileName: file.name,
          title: title,
          subjectName: subjectName,
          department: department,
          stage: stage,
          section: section,
          semester: semester,
          lectureType: lectureType,
          description: description,
          uploaderId: uploaderId,
          uploaderName: uploaderName,
          uploaderRole: uploaderRole,
          onProgress: onProgress,
        );
        if (streamerRes != null && streamerRes.success) {
          return streamerRes;
        }
        debugPrint('[~] Streamer upload bypassed or unavailable. Activating direct Telegram chunked multipart pipeline...');
      }

      // ── النمط الأول: الملفات العادية (أصغر من أو تساوي 19MB) تُرفع مباشرة ──
      if (totalBytes <= 19 * 1024 * 1024) {
        final captionLines = [
          '📚 ${title.trim()}',
          '📖 المقرر: ${subjectName.trim()}',
          '🏛 القسم: $department | المرحلة: $stage',
        ];
        if (section != 'ALL') {
          captionLines.add('🏷️ شعبة: $section');
        }
        if (description != null && description.trim().isNotEmpty) {
          captionLines.add('📝 ملاحظات: ${description.trim()}');
        }
        captionLines.add('👤 نُشر بواسطة: $uploaderName ($uploaderRole)');
        final caption = captionLines.join('\n');

        const initialStatus = 'جاري الرفع...';
        onProgress?.call(initialStatus, 0.05);
        onDetailedProgress?.call(0, totalBytes, 0.05, initialStatus);

        final response = await _sendDocumentWithRetry(
          uri: uri,
          chatId: channelId.toString(),
          caption: caption,
          fileBytes: fileBytes,
          fileName: file.name,
          maxAttempts: 3,
          onProgress: onProgress,
          onBytesProgress: (sent, total, ratio) {
            final mappedProg = (ratio * 0.85).clamp(0.05, 0.85);
            const status = 'جاري الرفع...';
            onProgress?.call(status, mappedProg);
            onDetailedProgress?.call(sent, total, mappedProg, status);
          },
        );

        if (response != null && response.statusCode == 200) {
          final data = jsonDecode(utf8.decode(response.bodyBytes));
          if (data['ok'] == true && data['result'] != null) {
            final result = data['result'];
            final msgId = result['message_id'] as int?;
            final doc = result['document'];
            String? fileId = doc?['file_id']?.toString();
            String detectedMime = doc?['mime_type']?.toString() ?? realMime;

            if (fileId == null) {
              if (result['video'] != null) {
                fileId = result['video']['file_id']?.toString();
                detectedMime = result['video']['mime_type']?.toString() ?? 'video/mp4';
              } else if (result['photo'] is List && (result['photo'] as List).isNotEmpty) {
                fileId = (result['photo'] as List).last['file_id']?.toString();
                detectedMime = 'image/jpeg';
              } else if (result['animation'] != null) {
                fileId = result['animation']['file_id']?.toString();
                detectedMime = result['animation']['mime_type']?.toString() ?? 'video/mp4';
              }
            }

            onProgress?.call('جاري المعالجة...', 0.90);
            onDetailedProgress?.call(totalBytes, totalBytes, 0.90, 'جاري المعالجة...');

            String? directUrl;
            if (fileId != null) {
              directUrl = await resolveFileUrl(fileId);
            }

            final lecturePayload = {
              'title': title.trim(),
              'subject_name': subjectName.trim(),
              'department': department,
              'stage': stage,
              'semester': semester,
              'type': lectureType,
              'drive_url': directUrl ?? 'telegram',
              'description': '${description?.trim() ?? ''} [SECTION:$section]'.trim(),
              'professor_name': null,
              'uploader_id': uploaderId,
              'uploader_name': uploaderName,
              'uploader_role': uploaderRole,
              'telegram_channel_id': channelId,
              'telegram_message_id': msgId,
              'telegram_file_id': fileId,
              'file_name': file.name,
              'file_size_bytes': totalBytes,
              'mime_type': detectedMime,
              'duration_seconds': 0,
            };

            final lectureModel = LectureModel.fromJson(lecturePayload);
            bool dbOk = await SupabaseService().createLecture(lectureModel);
            if (!dbOk) {
              try {
                final dbSafe = lectureModel.toDbJson();
                await SupabaseService().client.from('lectures').insert(dbSafe);
                dbOk = true;
              } catch (dbErr) {
                debugPrint('[-] Direct db insert error: $dbErr');
              }
            }

            if (!dbOk) {
              return UploadLectureResult(
                success: false,
                message: 'تعذر حفظ بيانات المحاضرة في قاعدة البيانات. يرجى المحاولة مرة أخرى.',
              );
            }

            onProgress?.call('تم الرفع', 1.0);
            onDetailedProgress?.call(totalBytes, totalBytes, 1.0, 'تم الرفع');

            return UploadLectureResult(
              success: true,
              message: 'تم الرفع بنجاح',
              telegramMessageId: msgId,
              fileId: fileId,
              fileName: file.name,
              fileSizeBytes: totalBytes,
            );
          }
        }

        final statusCode = response?.statusCode ?? 500;
        final body = response?.body ?? '';
        return UploadLectureResult(
          success: false,
          message: 'فشل الرفع ($statusCode): $body',
        );
      }

      // ── النمط المتطور للملفات الكبيرة (> 19MB حتى 2GB): تقسيم سحابي ذكي ومستقر ──
      final chunkSize = 19 * 1024 * 1024; // 19 MB per part (safe for Telegram getFile & sendDocument)
      final totalParts = (totalBytes / chunkSize).ceil();
      final List<Map<String, dynamic>> uploadedParts = [];
      int overallBytesSentSoFar = 0;

      const startStatus = 'جاري الرفع...';
      onProgress?.call(startStatus, 0.05);
      onDetailedProgress?.call(0, totalBytes, 0.05, startStatus);

      for (int partIdx = 0; partIdx < totalParts; partIdx++) {
        final start = partIdx * chunkSize;
        final end = (start + chunkSize > totalBytes) ? totalBytes : start + chunkSize;
        final partBytes = Uint8List.view(fileBytes.buffer, fileBytes.offsetInBytes + start, end - start);
        final partNum = partIdx + 1;
        final partFileName = '${file.name}.part$partNum';

        final partCaptionLines = [
          '📚 ${title.trim()} (جزء $partNum من $totalParts)',
          '📖 المقرر: ${subjectName.trim()}',
          '🏛 القسم: $department | المرحلة: $stage',
        ];
        if (section != 'ALL') {
          partCaptionLines.add('🏷️ شعبة: $section');
        }
        partCaptionLines.add('📦 حجم الجزء: ${_formatBytes(partBytes.length)} | الإجمالي: ${_formatBytes(totalBytes)}');
        partCaptionLines.add('👤 نُشر بواسطة: $uploaderName ($uploaderRole)');
        final partCaption = partCaptionLines.join('\n');

        final partResponse = await _sendDocumentWithRetry(
          uri: uri,
          chatId: channelId.toString(),
          caption: partCaption,
          fileBytes: partBytes,
          fileName: partFileName,
          maxAttempts: 3,
          onProgress: (status, prog) {
            // Keep main loop informed
          },
          onBytesProgress: (sent, total, ratio) {
            final currentTotalSent = overallBytesSentSoFar + sent;
            final overallRatio = (currentTotalSent / totalBytes).clamp(0.0, 1.0);
            final mappedProg = (overallRatio * 0.85).clamp(0.05, 0.85);
            const status = 'جاري الرفع...';
            onProgress?.call(status, mappedProg);
            onDetailedProgress?.call(currentTotalSent, totalBytes, mappedProg, status);
          },
        );

        if (partResponse == null || partResponse.statusCode != 200) {
          return UploadLectureResult(
            success: false,
            message: 'تعذر رفع الجزء $partNum ($totalParts) كود (${partResponse?.statusCode ?? 500}).',
          );
        }

        final data = jsonDecode(utf8.decode(partResponse.bodyBytes));
        final resObj = data['result'];
        final msgId = resObj['message_id'] as int?;
        final doc = resObj['document'];
        final fileId = doc?['file_id']?.toString();

        uploadedParts.add({
          'part': partNum,
          'message_id': msgId,
          'file_id': fileId,
          'size': partBytes.length,
        });
        overallBytesSentSoFar += partBytes.length;
      }

      // تم رفع كافة الأجزاء بنجاح تام إلى سحابة تيليجرام
      final primaryMsgId = uploadedParts.first['message_id'] as int?;
      final partsJson = jsonEncode(uploadedParts);
      final partsDescriptor = 'telegram:parts:$partsJson';

      onProgress?.call('جاري المعالجة...', 0.90);
      onDetailedProgress?.call(totalBytes, totalBytes, 0.90, 'جاري المعالجة...');

      final lecturePayload = {
        'title': title.trim(),
        'subject_name': subjectName.trim(),
        'department': department,
        'stage': stage,
        'semester': semester,
        'type': lectureType,
        'drive_url': partsDescriptor,
        'description': '${description?.trim() ?? ''} [SECTION:$section] [PARTS:$totalParts]'.trim(),
        'professor_name': null,
        'uploader_id': uploaderId,
        'uploader_name': uploaderName,
        'uploader_role': uploaderRole,
        'telegram_channel_id': channelId,
        'telegram_message_id': primaryMsgId,
        'telegram_file_id': partsDescriptor,
        'file_name': file.name,
        'file_size_bytes': totalBytes,
        'mime_type': realMime,
        'duration_seconds': 0,
      };

      final lectureModel = LectureModel.fromJson(lecturePayload);
      bool dbOk = await SupabaseService().createLecture(lectureModel);
      if (!dbOk) {
        try {
          final dbSafe = lectureModel.toDbJson();
          await SupabaseService().client.from('lectures').insert(dbSafe);
          dbOk = true;
        } catch (dbErr) {
          debugPrint('[-] Direct db insert error: $dbErr');
        }
      }

      if (!dbOk) {
        return UploadLectureResult(
          success: false,
          message: 'تعذر حفظ بيانات المحاضرة في قاعدة البيانات. يرجى المحاولة مرة أخرى.',
        );
      }

      onProgress?.call('تم الرفع', 1.0);
      onDetailedProgress?.call(totalBytes, totalBytes, 1.0, 'تم الرفع');

      return UploadLectureResult(
        success: true,
        message: 'تم الرفع بنجاح',
        telegramMessageId: primaryMsgId,
        fileId: partsDescriptor,
        fileName: file.name,
        fileSizeBytes: totalBytes,
      );
    } catch (e) {
      debugPrint('[-] Upload lecture cloud error: $e');
      return UploadLectureResult(
        success: false,
        message: 'انقطع الاتصال أثناء الرفع. يرجى إعادة المحاولة.',
      );
    }
  }
}
