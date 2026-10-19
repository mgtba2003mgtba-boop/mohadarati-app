import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:file_picker/file_picker.dart';
import '../core/constants/app_constants.dart';
import '../models/lecture_model.dart';
import 'supabase_service.dart';

/// نتيجة عملية رفع المحاضرة
class UploadLectureResult {
  final bool success;
  final String message;
  final int? telegramMessageId;
  final String? fileName;
  final int? fileSizeBytes;

  UploadLectureResult({
    required this.success,
    required this.message,
    this.telegramMessageId,
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

  /// اختيار ملف محاضرة من ذاكرة الجهاز (مستند PDF/Office أو صورة توضيحية)
  Future<PlatformFile?> pickLectureFile() async {
    try {
      final List<PlatformFile> files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'docx', 'doc', 'pptx', 'ppt', 'png', 'jpg', 'jpeg', 'webp', 'zip', 'rar'],
      );

      if (files.isNotEmpty) {
        return files.first;
      }
      return null;
    } catch (e) {
      debugPrint('[-] FilePicker error: $e');
      return null;
    }
  }

  /// اختيار صورة أو ملف PDF (للجداول الأسبوعية وجداول الامتحانات والبوسترات)
  Future<PlatformFile?> pickImageOrPdfFile() async {
    try {
      final List<PlatformFile> files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['png', 'jpg', 'jpeg', 'webp', 'pdf'],
      );

      if (files.isNotEmpty) {
        return files.first;
      }
      return null;
    } catch (e) {
      debugPrint('[-] FilePicker error: $e');
      return null;
    }
  }

  /// اختيار صورة فقط (لبنل البوسترات والإعلانات المصورة)
  Future<PlatformFile?> pickImageOnly() async {
    try {
      final List<PlatformFile> files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['png', 'jpg', 'jpeg', 'webp'],
      );

      if (files.isNotEmpty) {
        return files.first;
      }
      return null;
    } catch (e) {
      debugPrint('[-] FilePicker error: $e');
      return null;
    }
  }

  /// قراءة بايتات الملف بأمان عبر مختلف المنصات (Web و Desktop و Mobile)
  Future<Uint8List> _getFileBytes(PlatformFile file) async {
    return await file.readAsBytes();
  }

  /// حساب حجم الملف بالبايت
  Future<int> getFileSize(PlatformFile file) async {
    try {
      final len = await file.length();
      if (len != null) return len;
    } catch (_) {}
    return 0;
  }

  /// تنسيق حجم الملف للعرض البشري
  String _formatBytes(int bytes) {
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} ميغابايت';
    } else {
      return '${(bytes / 1024).toStringAsFixed(0)} كيلوبايت';
    }
  }

  /// إرسال مستند إلى تيليجرام مع إعادة المحاولة التلقائية عند تذبذب الاتصال (Exponential Backoff Auto-Retry)
  Future<http.Response?> _sendDocumentWithRetry({
    required Uri uri,
    required String chatId,
    required String caption,
    required Uint8List fileBytes,
    required String fileName,
    int maxAttempts = 3,
    void Function(String status, double? progress)? onProgress,
  }) async {
    http.Response? lastResponse;
    dynamic lastError;

    for (int attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        if (attempt > 1) {
          onProgress?.call('تذبذب في شبكة الاتصال، إعادة المحاولة تلقائياً ($attempt/$maxAttempts)...', 0.4);
          debugPrint('[~] Retrying Telegram upload attempt $attempt of $maxAttempts after backoff...');
          await Future.delayed(Duration(seconds: (attempt - 1) * 2));
        } else {
          onProgress?.call('جاري رفع الملف إلى السحابة المباشرة...', 0.3);
        }

        final request = http.MultipartRequest('POST', uri);
        request.fields['chat_id'] = chatId;
        request.fields['caption'] = caption;
        request.files.add(
          http.MultipartFile.fromBytes(
            'document',
            fileBytes,
            filename: fileName,
          ),
        );

        final streamedResponse = await request.send().timeout(const Duration(minutes: 5));
        final response = await http.Response.fromStream(streamedResponse);
        lastResponse = response;

        if (response.statusCode == 200) {
          return response;
        }

        // أخطاء غير قابلة للإعادة (مثل ملف كبير جداً أو توكن غير صحيح)
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

  /// جلب رابط مباشر جديد للملف في حال الحاجة لتحديث الرابط
  Future<String?> resolveFileUrl(String fileId) async {
    try {
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
    return null;
  }

  /// رفع أي ملف أو صورة مباشرة إلى سحابة تيليجرام (للجداول والبوسترات)
  Future<UploadGeneralFileResult> uploadFileToTelegram({
    required PlatformFile file,
    String? caption,
    String fileType = 'general', // 'schedule' أو 'banner' أو 'general'
    void Function(String status, double? progress)? onProgress,
  }) async {
    try {
      onProgress?.call('جاري قراءة وتجهيز الملف...', 0.1);
      final Uint8List fileBytes = await _getFileBytes(file);
      if (fileBytes.isEmpty) {
        return UploadGeneralFileResult(
          success: false,
          message: 'تعذر قراءة بيانات الملف من المتصفح، يرجى المحاولة مرة أخرى.',
        );
      }

      if (fileBytes.length > 50 * 1024 * 1024) {
        return UploadGeneralFileResult(
          success: false,
          message: 'حجم الملف يتجاوز الحد الأقصى المسموح به للرفع السحابي (50 ميغابايت).',
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
        fileName: file.name,
        maxAttempts: 3,
        onProgress: onProgress,
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

          onProgress?.call('تم رفع الملف بنجاح!', 1.0);

          return UploadGeneralFileResult(
            success: true,
            message: 'تم رفع الملف إلى سحابة تيليجرام بنجاح',
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
      String friendlyMessage = 'فشل الرفع من سحابة تيليجرام ($statusCode)';
      if (statusCode == 400 && body.contains('file is too big')) {
        friendlyMessage = 'حجم الملف يتجاوز الحد المسموح به في تيليجرام (50 ميغابايت).';
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
        message: 'انقطع الاتصال بالسحابة أثناء الرفع بعد عدة محاولات تلقائية. يرجى التأكد من استقرار شبكة الإنترنت وإعادة المحاولة.',
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

  /// رفع ملف المحاضرة والميتا داتا مباشرة إلى سحابة تيليجرام وقاعدة بيانات سوبابيز
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
  }) async {
    try {
      onProgress?.call('جاري قراءة وتجهيز بيانات ملف المحاضرة...', 0.1);
      final Uint8List fileBytes = await _getFileBytes(file);
      if (fileBytes.isEmpty) {
        return UploadLectureResult(
          success: false,
          message: 'تعذر قراءة بيانات ملف المحاضرة من المتصفح، يرجى إعادة اختيار الملف.',
        );
      }

      if (fileBytes.length > 50 * 1024 * 1024) {
        return UploadLectureResult(
          success: false,
          message: 'حجم الملف يتجاوز الحد الأقصى المسموح به للرفع المباشر (50 ميغابايت). يرجى ضغط الملف أو استخدام رابط Google Drive للملفات الكبيرة جداً.',
        );
      }

      // 1. صياغة التسمية والوصف لقناة تيليجرام
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

      // 2. الرفع المباشر عبر Telegram Bot API مع إعادة المحاولة التلقائية عند تذبذب الشبكة
      final botToken = AppConstants.lecturesBotToken;
      final channelId = AppConstants.lecturesChannelId;
      final uri = Uri.parse('https://api.telegram.org/bot$botToken/sendDocument');

      onProgress?.call('جاري رفع المحاضرة (${_formatBytes(fileBytes.length)}) إلى السحابة...', 0.25);

      final response = await _sendDocumentWithRetry(
        uri: uri,
        chatId: channelId.toString(),
        caption: caption,
        fileBytes: fileBytes,
        fileName: file.name,
        maxAttempts: 3,
        onProgress: onProgress,
      );

      if (response != null && response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        if (data['ok'] == true && data['result'] != null) {
          final result = data['result'];
          final msgId = result['message_id'] as int?;
          final doc = result['document'];
          String? fileId = doc?['file_id']?.toString();
          String realMime = doc?['mime_type']?.toString() ?? 'application/octet-stream';

          if (fileId == null) {
            if (result['video'] != null) {
              fileId = result['video']['file_id']?.toString();
              realMime = result['video']['mime_type']?.toString() ?? 'video/mp4';
            } else if (result['photo'] is List && (result['photo'] as List).isNotEmpty) {
              fileId = (result['photo'] as List).last['file_id']?.toString();
              realMime = 'image/jpeg';
            } else if (result['animation'] != null) {
              fileId = result['animation']['file_id']?.toString();
              realMime = result['animation']['mime_type']?.toString() ?? 'video/mp4';
            }
          }

          onProgress?.call('تم رفع الملف بنجاح! جاري معالجة المعرّف السحابي...', 0.75);

          // 3. جلب مسار التحميل المباشر السحابي الدائم
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
              debugPrint('[-] Error getting lecture file path: $e');
            }
          }

          onProgress?.call('جاري حفظ بيانات المحاضرة ومزامنتها للطلبة...', 0.9);

          // 4. حفظ بيانات المحاضرة سحابياً في جدول Supabase مباشرة
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
            'file_size_bytes': fileBytes.length,
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
              message: 'تم رفع الملف بنجاح إلى السحابة، ولكن تعذر حفظ بيانات المحاضرة في قاعدة البيانات. يرجى المحاولة مرة أخرى.',
            );
          }

          onProgress?.call('تم نشر المحاضرة ومزامنتها بنجاح!', 1.0);

          return UploadLectureResult(
            success: true,
            message: 'تم نشر ورفع المحاضرة إلى السحابة بنجاح ومزامنتها للطلبة',
            telegramMessageId: msgId,
            fileName: file.name,
            fileSizeBytes: fileBytes.length,
          );
        }
      }

      final statusCode = response?.statusCode ?? 500;
      final body = response?.body ?? '';
      String friendlyMessage = 'فشل الرفع من سحابة تيليجرام ($statusCode)';
      if (statusCode == 400 && body.contains('file is too big')) {
        friendlyMessage = 'حجم الملف يتجاوز الحد المسموح به في تيليجرام (50 ميغابايت). يرجى ضغط الملف أو استخدام رابط درايف.';
      } else if (statusCode == 429) {
        friendlyMessage = 'تم تجاوز معدل الطلبات المسموح به مؤقتاً، يرجى الانتظار دقيقة والمحاولة مجدداً.';
      } else if (body.isNotEmpty) {
        friendlyMessage = '$friendlyMessage: $body';
      }

      return UploadLectureResult(
        success: false,
        message: friendlyMessage,
      );
    } catch (e) {
      debugPrint('[-] Upload lecture cloud error: $e');
      return UploadLectureResult(
        success: false,
        message: 'انقطع الاتصال بالسحابة أثناء الرفع بعد عدة محاولات تلقائية. يرجى التأكد من استقرار شبكة الإنترنت وإعادة المحاولة.',
      );
    }
  }
}
