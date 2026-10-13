import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/constants/app_constants.dart';
import '../core/theme/app_theme.dart';
import 'app_icon_badge.dart';
import 'web_iframe_viewer.dart';

/// نافذة المعاينة التفاعلية الذكية المدمجة بملء الشاشة
/// تعرض ملفات الـ PDF، الصور، الفيديوهات والمستندات داخل التطبيق مباشرة دون تحميل قسري
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
  bool _isLoading = true;
  bool _hasError = false;

  bool get _isImage {
    final lower = (widget.fileName ?? widget.rawUrl).toLowerCase();
    final mime = (widget.mimeType ?? '').toLowerCase();
    return mime.startsWith('image/') ||
        lower.endsWith('.png') ||
        lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.webp') ||
        lower.endsWith('.gif');
  }

  bool get _isPdf {
    final lower = (widget.fileName ?? widget.rawUrl).toLowerCase();
    final mime = (widget.mimeType ?? '').toLowerCase();
    return mime == 'application/pdf' || lower.endsWith('.pdf');
  }

  bool get _isVideo {
    final lower = (widget.fileName ?? widget.rawUrl).toLowerCase();
    final mime = (widget.mimeType ?? '').toLowerCase();
    return mime.startsWith('video/') ||
        lower.endsWith('.mp4') ||
        lower.endsWith('.mkv') ||
        lower.endsWith('.webm') ||
        lower.endsWith('.mov') ||
        lower.endsWith('.avi');
  }

  bool get _isDrive {
    return widget.rawUrl.contains('drive.google.com');
  }

  /// توليد رابط المعاينة المباشر المخصص للعارض المدمج
  String get _embeddedPreviewUrl {
    final clean = widget.rawUrl.trim();

    // 1. روابط Google Drive
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

    // 2. ملفات الـ PDF والمستندات عبر سحابة تيليجرام أو السيرفر الخارجي
    if (_isPdf || !_isImage) {
      // استخدام Google Docs Viewer المدمج لقراءة وعرض المستند بدون تنزيل
      return 'https://docs.google.com/viewer?url=${Uri.encodeComponent(clean)}&embedded=true';
    }

    return clean;
  }

  /// رابط تنزيل الملف الصريح
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
            Text(
              widget.title,
              style: GoogleFonts.cairo(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (widget.subtitle != null && widget.subtitle!.isNotEmpty)
              Text(
                widget.subtitle!,
                style: GoogleFonts.cairo(color: const Color(0xFF94A3B8), fontSize: 11),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
          ],
        ),
        actions: [
          // زر فتح في نافذة مستقلة
          IconButton(
            icon: const Icon(Icons.open_in_new_rounded, color: Colors.white70, size: 20),
            tooltip: 'فتح في تبويب مستقل',
            onPressed: () => _launchExternal(_embeddedPreviewUrl),
          ),

          // زر تنزيل الملف الصريح (Manual Download)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: ElevatedButton.icon(
              onPressed: () => _launchExternal(_downloadTargetUrl),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              icon: const Icon(Icons.download_rounded, size: 16),
              label: Text(
                'تنزيل',
                style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
      body: SizedBox.expand(
        child: _isImage
            ? _buildImageViewer(resolvedImageUrl)
            : _buildDocumentOrVideoViewer(_embeddedPreviewUrl),
      ),
    );
  }

  /// عارض الصور التفاعلي (Interactive Pinch-to-Zoom & Pan)
  Widget _buildImageViewer(String imageUrl) {
    return InteractiveViewer(
      minScale: 0.5,
      maxScale: 6.0,
      child: Center(
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
                  Text('جاري فتح الصورة...', style: GoogleFonts.cairo(color: Colors.white70, fontSize: 13)),
                ],
              ),
            );
          },
          errorBuilder: (context, error, stackTrace) => _buildErrorState('تعذر تحميل الصورة داخل المعاينة'),
        ),
      ),
    );
  }

  /// عارض المستندات والـ PDF والفيديوهات المدمج (In-App Embedded Viewer)
  Widget _buildDocumentOrVideoViewer(String embedUrl) {
    return Stack(
      children: [
        // عارض الـ IFrame المدمج داخل التطبيق
        Positioned.fill(
          child: buildWebIFrame(
            url: embedUrl,
            title: widget.title,
          ),
        ),

        // شريط إرشادي سفلي أنيق
        Positioned(
          left: 16,
          right: 16,
          bottom: 16,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B).withValues(alpha: 0.95),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white12),
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 15, offset: const Offset(0, 4)),
              ],
            ),
            child: Row(
              children: [
                Icon(
                  _isPdf ? Icons.picture_as_pdf_rounded : _isVideo ? Icons.videocam_rounded : Icons.description_rounded,
                  color: AppTheme.accent,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _isPdf
                        ? 'المعاينة المباشرة للمستند نشطة • يمكنك التمرير وقراءة الصفحات'
                        : 'معاينة الوسائط المدمجة داخل التطبيق',
                    style: GoogleFonts.cairo(color: const Color(0xFFCBD5E1), fontSize: 11),
                  ),
                ),
                TextButton.icon(
                  onPressed: () => _launchExternal(_embeddedPreviewUrl),
                  style: TextButton.styleFrom(
                    foregroundColor: AppTheme.accent,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
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
            const Icon(Icons.broken_image_rounded, color: Colors.white54, size: 54),
            const SizedBox(height: 14),
            Text(
              message,
              style: GoogleFonts.cairo(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 18),
            ElevatedButton.icon(
              onPressed: () => _launchExternal(_downloadTargetUrl),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: const Icon(Icons.download_rounded, size: 18, color: Colors.white),
              label: Text('تنزيل الملف المباشر', style: GoogleFonts.cairo(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }
}
