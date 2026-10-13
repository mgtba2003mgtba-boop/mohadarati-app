import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/constants/app_constants.dart';
import '../core/theme/app_theme.dart';
import 'web_iframe_viewer.dart';

/// نافذة المعاينة التفاعلية الذكية المدمجة بملء الشاشة
/// تعرض ملفات الـ PDF، الصور، والمستندات داخل التطبيق مباشرة دون تنزيل قسري
class AppMediaPreviewModal extends StatefulWidget {
  final String title;
  final String? subtitle;
  final String rawUrl;
  final String? explicitDownloadUrl;
  final String? fileName;
  final String? mimeType;

  const AppMediaPreviewModal({
    super.key,
    required this.title,
    this.subtitle,
    required this.rawUrl,
    this.explicitDownloadUrl,
    this.fileName,
    this.mimeType,
  });

  /// دالة إظهار نافذة المعاينة المدمجة
  static Future<void> show({
    required BuildContext context,
    required String title,
    String? subtitle,
    required String url,
    String? downloadUrl,
    String? fileName,
    String? mimeType,
  }) {
    return Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => AppMediaPreviewModal(
          title: title,
          subtitle: subtitle,
          rawUrl: url,
          explicitDownloadUrl: downloadUrl,
          fileName: fileName,
          mimeType: mimeType,
        ),
      ),
    );
  }

  @override
  State<AppMediaPreviewModal> createState() => _AppMediaPreviewModalState();
}

class _AppMediaPreviewModalState extends State<AppMediaPreviewModal> {
  final TransformationController _transformController = TransformationController();
  double _rotationAngle = 0; // 0, 90, 180, 270

  bool get _isPdf {
    final lowerName = (widget.fileName ?? '').toLowerCase();
    final lowerUrl = widget.rawUrl.toLowerCase();
    final mime = (widget.mimeType ?? '').toLowerCase();

    if (mime == 'application/pdf') return true;
    if (lowerName.endsWith('.pdf') || lowerUrl.contains('.pdf')) return true;
    return false;
  }

  bool get _isImage {
    final lowerName = (widget.fileName ?? '').toLowerCase();
    final lowerUrl = widget.rawUrl.toLowerCase();
    final mime = (widget.mimeType ?? '').toLowerCase();

    if (mime.startsWith('image/')) return true;

    final imageExtensions = ['.png', '.jpg', '.jpeg', '.webp', '.gif', '.bmp', '.svg'];
    for (final ext in imageExtensions) {
      if (lowerName.endsWith(ext) || lowerUrl.contains(ext)) return true;
    }

    if (lowerUrl.contains('photos/') || lowerUrl.contains('/photo/') || lowerUrl.contains('image')) {
      return true;
    }

    // في حال عدم وجود امتداد، إذا لم تكن PDF وكانت صورة من تيليجرام
    if (!_isPdf && (lowerUrl.contains('/photos') || lowerName.contains('بوستر') || lowerName.contains('صورة') || lowerName.contains('جدول'))) {
      return true;
    }

    return false;
  }

  bool get _isDrive {
    return widget.rawUrl.contains('drive.google.com');
  }

  /// توليد رابط المعاينة المباشر المخصص للعارض المدمج
  String get _embeddedPreviewUrl {
    final clean = widget.rawUrl.trim();

    // 1. ملفات PDF: فتحها عبر عارض PDF.js المدمج المحلي (بدون Google Docs وبدون تنزيل)
    if (_isPdf) {
      final proxied = AppConstants.resolveImageUrl(clean);
      return 'pdf_viewer.html?file=${Uri.encodeComponent(proxied)}';
    }

    // 2. صور (في حال تم استدعاء الـ IFrame)
    if (_isImage) {
      return AppConstants.resolveImageUrl(clean);
    }

    // 3. روابط Google Drive القديمة (عرض فقط)
    if (_isDrive) {
      if (clean.contains('/file/d/')) {
        final regExp = RegExp(r'file/d/([a-zA-Z0-9_-]+)');
        final match = regExp.firstMatch(clean);
        if (match != null && match.groupCount >= 1) {
          final fileId = match.group(1);
          return 'https://drive.google.com/file/d/$fileId/preview';
        }
      }
      return clean;
    }

    // 4. مستندات أخرى عبر عارض المستندات كخيار احتياطي
    return 'https://docs.google.com/viewer?url=${Uri.encodeComponent(clean)}&embedded=true';
  }

  /// رابط تنزيل الملف الصريح لمن يرغب بحفظ نسخة
  String get _downloadTargetUrl {
    if (widget.explicitDownloadUrl != null && widget.explicitDownloadUrl!.trim().isNotEmpty) {
      return widget.explicitDownloadUrl!.trim();
    }
    return widget.rawUrl.trim();
  }

  Future<void> _launchExternal(String url) async {
    final uri = Uri.parse(url.trim());
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر فتح الرابط: $e'), backgroundColor: AppTheme.danger),
        );
      }
    }
  }

  void _rotateImage() {
    setState(() {
      _rotationAngle = (_rotationAngle + 90) % 360;
    });
  }

  void _resetZoom() {
    _transformController.value = Matrix4.identity();
  }

  @override
  void dispose() {
    _transformController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final resolvedImageUrl = AppConstants.resolveImageUrl(widget.rawUrl);

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E293B),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded, color: Colors.white, size: 26),
          tooltip: 'إغلاق المعاينة',
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _isImage ? Icons.image_rounded : _isPdf ? Icons.picture_as_pdf_rounded : Icons.description_rounded,
                  color: AppTheme.accent,
                  size: 16,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    widget.title,
                    style: GoogleFonts.cairo(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            if (widget.subtitle != null && widget.subtitle!.isNotEmpty)
              Text(
                widget.subtitle!,
                style: GoogleFonts.cairo(color: const Color(0xFF94A3B8), fontSize: 10),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
          ],
        ),
        actions: [
          if (_isImage) ...[
            IconButton(
              icon: const Icon(Icons.rotate_right_rounded, color: Colors.white70, size: 20),
              tooltip: 'تدوير الصورة',
              onPressed: _rotateImage,
            ),
            IconButton(
              icon: const Icon(Icons.restart_alt_rounded, color: Colors.white70, size: 20),
              tooltip: 'إعادة ضبط الحجم',
              onPressed: _resetZoom,
            ),
          ],

          // فتح المعاينة في تبويب مستقل عند الحاجة
          IconButton(
            icon: const Icon(Icons.open_in_new_rounded, color: Colors.white70, size: 20),
            tooltip: 'فتح المعاينة بملء الشاشة',
            onPressed: () {
              if (_isImage) {
                _launchExternal(resolvedImageUrl);
              } else {
                _launchExternal(_embeddedPreviewUrl);
              }
            },
          ),

          // خيار اختياري هادئ لحفظ نسخة على الجهاز
          IconButton(
            icon: const Icon(Icons.download_rounded, color: Colors.white60, size: 20),
            tooltip: 'حفظ نسخة على جهازك',
            onPressed: () => _launchExternal(_downloadTargetUrl),
          ),
        ],
      ),
      body: SizedBox.expand(
        child: _isImage
            ? _buildImageViewer(resolvedImageUrl)
            : _buildDocumentViewer(_embeddedPreviewUrl),
      ),
    );
  }

  /// عارض الصور التفاعلي (Interactive Pinch-to-Zoom & Pan)
  Widget _buildImageViewer(String imageUrl) {
    return Container(
      color: const Color(0xFF0F172A),
      child: Center(
        child: InteractiveViewer(
          transformationController: _transformController,
          minScale: 0.5,
          maxScale: 8.0,
          child: RotatedBox(
            quarterTurns: (_rotationAngle / 90).round(),
            child: Image.network(
              imageUrl,
              fit: BoxFit.contain,
              loadingBuilder: (context, child, progress) {
                if (progress == null) return child;
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(color: AppTheme.primary, strokeWidth: 2.5),
                      const SizedBox(height: 14),
                      Text(
                        'جاري فتح ومعاينة الصورة...',
                        style: GoogleFonts.cairo(color: Colors.white70, fontSize: 13),
                      ),
                    ],
                  ),
                );
              },
              errorBuilder: (context, error, stackTrace) => _buildErrorState('تعذر فتح الصورة في المعاينة'),
            ),
          ),
        ),
      ),
    );
  }

  /// عارض المستندات والـ PDF المدمج دون أي تحميل قسري
  Widget _buildDocumentViewer(String embedUrl) {
    return Stack(
      children: [
        // عارض الـ IFrame المدمج داخل التطبيق
        Positioned.fill(
          child: buildWebIFrame(
            url: embedUrl,
            title: widget.title,
          ),
        ),

        // شريط إرشادي سفلي خفيف
        Positioned(
          left: 16,
          right: 16,
          bottom: 12,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B).withValues(alpha: 0.95),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white12),
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 10, offset: const Offset(0, 3)),
              ],
            ),
            child: Row(
              children: [
                Icon(
                  _isPdf ? Icons.picture_as_pdf_rounded : Icons.description_rounded,
                  color: AppTheme.accent,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _isPdf
                        ? 'معاينة المستند نشطة • مرر للاطلاع على كافة الصفحات'
                        : 'معاينة المستند المدمجة',
                    style: GoogleFonts.cairo(color: const Color(0xFFCBD5E1), fontSize: 11),
                  ),
                ),
                TextButton.icon(
                  onPressed: () => _launchExternal(_embeddedPreviewUrl),
                  style: TextButton.styleFrom(
                    foregroundColor: AppTheme.accent,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  icon: const Icon(Icons.fullscreen_rounded, size: 16),
                  label: Text('ملء الشاشة', style: GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildErrorState(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.image_not_supported_rounded, color: Colors.white54, size: 48),
            const SizedBox(height: 12),
            Text(
              message,
              style: GoogleFonts.cairo(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () => setState(() {}),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              icon: const Icon(Icons.refresh_rounded, size: 16, color: Colors.white),
              label: Text('إعادة المحاولة', style: GoogleFonts.cairo(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }
}
