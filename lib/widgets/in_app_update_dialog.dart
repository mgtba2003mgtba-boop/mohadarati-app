import 'dart:async';
import 'dart:io' show File;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import '../core/theme/app_theme.dart';
import '../services/auto_update_service.dart';

/// ── نافذة التحديث الإجباري التلقائي (Mandatory In-App Update Dialog) ──────────
/// تظهر عند اكتشاف إصدار أحدث على السيرفر، مع شريط تقدم مباشر للتنزيل بنسبة مئوية
/// وتشغيل مباشر لمثبت النظام الرسمي بنقرة واحدة.
class InAppUpdateDialog extends StatefulWidget {
  final String version;
  final int versionCode;
  final String releaseNotes;
  final String apkUrl;

  const InAppUpdateDialog({
    super.key,
    required this.version,
    required this.versionCode,
    required this.releaseNotes,
    required this.apkUrl,
  });

  static Future<void> show(
    BuildContext context, {
    required String version,
    required int versionCode,
    required String releaseNotes,
    required String apkUrl,
  }) async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => InAppUpdateDialog(
        version: version,
        versionCode: versionCode,
        releaseNotes: releaseNotes,
        apkUrl: apkUrl,
      ),
    );
  }

  @override
  State<InAppUpdateDialog> createState() => _InAppUpdateDialogState();
}

class _InAppUpdateDialogState extends State<InAppUpdateDialog> {
  bool _isDownloading = false;
  double _progress = 0.0;
  int _receivedBytes = 0;
  int _totalBytes = 0;
  String? _errorMessage;
  bool _isDownloaded = false;
  String? _apkPath;

  Future<void> _startDownload() async {
    setState(() {
      _isDownloading = true;
      _errorMessage = null;
      _progress = 0.0;
      _receivedBytes = 0;
    });

    try {
      final cacheDir = await AutoUpdateService.getCacheDir();
      if (cacheDir == null) {
        throw Exception('تعذر الوصول لمجلد الذاكرة المؤقتة');
      }

      final targetFile = File('$cacheDir/Mohadarati_v${widget.versionCode}.apk');

      // إذا كان الملف محملاً مسبقاً وبحجم كامل
      if (await targetFile.exists() && await targetFile.length() > 15 * 1024 * 1024) {
        setState(() {
          _isDownloading = false;
          _isDownloaded = true;
          _progress = 1.0;
          _apkPath = targetFile.path;
        });
        await _installApk();
        return;
      }

      final client = http.Client();
      final request = http.Request('GET', Uri.parse(widget.apkUrl));
      final response = await client.send(request).timeout(const Duration(seconds: 180));

      if (response.statusCode != 200) {
        throw Exception('فشل الاتصال بسيرفر التحديث (${response.statusCode})');
      }

      _totalBytes = response.contentLength ?? (21 * 1024 * 1024);
      final sink = targetFile.openWrite();

      await for (final chunk in response.stream) {
        sink.add(chunk);
        _receivedBytes += chunk.length;
        if (mounted) {
          setState(() {
            _progress = (_receivedBytes / _totalBytes).clamp(0.0, 1.0);
          });
        }
      }

      await sink.flush();
      await sink.close();

      final finalSize = await targetFile.length();
      if (finalSize < 10 * 1024 * 1024) {
        throw Exception('الملف المنزّل غير مكتمل، يرجى إعادة المحاولة');
      }

      setState(() {
        _isDownloading = false;
        _isDownloaded = true;
        _progress = 1.0;
        _apkPath = targetFile.path;
      });

      // تشغيل التثبيت تلقائياً ومباشرة فور اكتمال التنزيل
      await _installApk();
    } catch (e) {
      if (mounted) {
        setState(() {
          _isDownloading = false;
          _errorMessage = e.toString().replaceAll('Exception: ', '');
        });
      }
    }
  }

  Future<void> _installApk() async {
    if (_apkPath != null) {
      await AutoUpdateService.installApkFile(_apkPath!);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Center(
        child: Container(
          width: 380,
          margin: const EdgeInsets.symmetric(horizontal: 24),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.25),
                blurRadius: 30,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // أيقونة ورأس النافذة
                Center(
                  child: Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF0284C7), Color(0xFF0369A1)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF0284C7).withValues(alpha: 0.35),
                          blurRadius: 16,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.system_update_rounded,
                      color: Colors.white,
                      size: 32,
                    ),
                  ),
                ),
                const SizedBox(height: 18),

                // العنوان ورقم الإصدار
                Text(
                  'يتوفر تحديث جديد للمنظومة',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.cairo(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 6),
                Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE0F2FE),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'الإصدار الجديد: ${widget.version}',
                      style: GoogleFonts.cairo(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF0369A1),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // ملاحظات التحديث
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.bolt_rounded, size: 16, color: Color(0xFFF59E0B)),
                          const SizedBox(width: 6),
                          Text(
                            'أبرز التحسينات والميزات:',
                            style: GoogleFonts.cairo(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFF334155),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        widget.releaseNotes.isNotEmpty
                            ? widget.releaseNotes
                            : 'تحسينات جذرية في سرعة الأداء وسلاسة النشر واستقرار التحديثات.',
                        style: GoogleFonts.cairo(
                          fontSize: 11.5,
                          height: 1.5,
                          color: const Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // حالة التنزيل وشريط التقدم
                if (_isDownloading) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: _progress > 0 ? _progress : null,
                      minHeight: 8,
                      backgroundColor: const Color(0xFFE2E8F0),
                      valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF0284C7)),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'جاري تنزيل التحديث...',
                        style: GoogleFonts.cairo(fontSize: 11, color: const Color(0xFF64748B)),
                      ),
                      Text(
                        '${(_progress * 100).toInt()}%',
                        style: GoogleFonts.cairo(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFF0284C7),
                        ),
                      ),
                    ],
                  ),
                ] else if (_errorMessage != null) ...[
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF2F2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _errorMessage!,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.cairo(fontSize: 11, color: const Color(0xFFDC2626)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: _startDownload,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0284C7),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: Text(
                      'إعادة المحاولة',
                      style: GoogleFonts.cairo(fontSize: 13, fontWeight: FontWeight.bold),
                    ),
                  ),
                ] else if (_isDownloaded) ...[
                  ElevatedButton.icon(
                    onPressed: _installApk,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF10B981),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      elevation: 0,
                    ),
                    icon: const Icon(Icons.install_mobile_rounded, size: 20),
                    label: Text(
                      'تثبيت التحديث الآن ⚡',
                      style: GoogleFonts.cairo(fontSize: 14, fontWeight: FontWeight.bold),
                    ),
                  ),
                ] else ...[
                  ElevatedButton.icon(
                    onPressed: _startDownload,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0284C7),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      elevation: 0,
                    ),
                    icon: const Icon(Icons.download_rounded, size: 20),
                    label: Text(
                      'تحديث المنظومة الآن 🚀',
                      style: GoogleFonts.cairo(fontSize: 14, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
