import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:file_picker/file_picker.dart';
import '../core/constants/app_constants.dart';

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

  /// اختيار ملف محاضرة من ذاكرة الجهاز (فيديو MP4/MKV أو مستند PDF/Office)
  Future<PlatformFile?> pickLectureFile() async {
    try {
      final List<PlatformFile> files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['mp4', 'mkv', 'avi', 'mov', 'pdf', 'docx', 'pptx', 'zip', 'rar'],
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

  /// حساب حجم الملف بالبايت
  Future<int> getFileSize(PlatformFile file) async {
    try {
      final len = await file.length();
      if (len != null) return len;
      final syncLen = file.lengthSync();
      if (syncLen != null) return syncLen;
    } catch (_) {}
    return 0;
  }

  /// رفع أي ملف أو صورة مباشرة إلى سحابة وسيرفر تيليجرام
  Future<UploadGeneralFileResult> uploadFileToTelegram({
    required PlatformFile file,
    String? caption,
    String fileType = 'general', // 'schedule' أو 'banner' أو 'general'
  }) async {
    try {
      final uploadUrl = Uri.parse('${AppConstants.telegramStreamerBaseUrl}/api/upload-file');
      final request = http.MultipartRequest('POST', uploadUrl);

      if (caption != null && caption.trim().isNotEmpty) {
        request.fields['caption'] = caption.trim();
      }
      request.fields['file_type'] = fileType;

      final Uint8List fileBytes = await file.readAsBytes();
      final int actualSize = fileBytes.length;

      request.files.add(
        http.MultipartFile.fromBytes(
          'file',
          fileBytes,
          filename: file.name,
        ),
      );

      final streamedResponse = await request.send().timeout(const Duration(minutes: 5));
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        final msgId = data['telegram_message_id'];
        final relativeUrl = data['file_url'] ?? '/api/file/$msgId';
        final fullUrl = '${AppConstants.telegramStreamerBaseUrl}$relativeUrl';

        return UploadGeneralFileResult(
          success: true,
          message: 'تم رفع الملف إلى سحابة تيليجرام بنجاح',
          telegramMessageId: msgId,
          fileUrl: fullUrl,
          fileName: file.name,
          fileSizeBytes: actualSize,
          mimeType: data['mime_type'],
        );
      } else {
        return UploadGeneralFileResult(
          success: false,
          message: 'فشل الرفع من سيرفر تيليجرام (${response.statusCode}): ${response.body}',
        );
      }
    } catch (e) {
      debugPrint('[-] Telegram general file upload error: $e');
      return UploadGeneralFileResult(
        success: false,
        message: 'حدث خطأ في الاتصال بسيرفر تيليجرام: $e',
      );
    }
  }

  /// رفع ملف المحاضرة والميتا داتا إلى سيرفر تيليجرام وسوبابيز
  Future<UploadLectureResult> uploadLecture({
    required PlatformFile file,
    required String title,
    required String subjectName,
    required String department,
    required String stage,
    required int semester,
    required String lectureType,
    String? professorName,
    String? description,
    required String uploaderId,
    required String uploaderName,
    required String uploaderRole,
  }) async {
    try {
      final uploadUrl = Uri.parse('${AppConstants.telegramStreamerBaseUrl}/api/upload-lecture');
      final request = http.MultipartRequest('POST', uploadUrl);

      request.fields['title'] = title.trim();
      request.fields['subject_name'] = subjectName.trim();
      request.fields['department'] = department;
      request.fields['stage'] = stage;
      request.fields['semester'] = semester.toString();
      request.fields['lecture_type'] = lectureType;
      if (professorName != null && professorName.trim().isNotEmpty) {
        request.fields['professor_name'] = professorName.trim();
      }
      if (description != null && description.trim().isNotEmpty) {
        request.fields['description'] = description.trim();
      }
      request.fields['uploader_id'] = uploaderId;
      request.fields['uploader_name'] = uploaderName;
      request.fields['uploader_role'] = uploaderRole;

      final Uint8List fileBytes = await file.readAsBytes();
      final int actualSize = fileBytes.length;

      request.files.add(
        http.MultipartFile.fromBytes(
          'file',
          fileBytes,
          filename: file.name,
        ),
      );

      final streamedResponse = await request.send().timeout(const Duration(minutes: 10));
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        return UploadLectureResult(
          success: true,
          message: 'تم رفع المحاضرة إلى سحابة الكلية بنجاح ومزامنتها للطلبة',
          telegramMessageId: data['telegram_message_id'],
          fileName: file.name,
          fileSizeBytes: actualSize,
        );
      } else {
        return UploadLectureResult(
          success: false,
          message: 'فشل الرفع من السيرفر (كود: ${response.statusCode}): ${response.body}',
        );
      }
    } catch (e) {
      debugPrint('[-] Upload error: $e');
      return UploadLectureResult(
        success: false,
        message: 'حدث خطأ في الاتصال بسيرفر المحاضرات: $e',
      );
    }
  }
}
