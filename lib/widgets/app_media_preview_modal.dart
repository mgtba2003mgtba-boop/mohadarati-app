import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import '../core/constants/app_constants.dart';
import '../core/theme/app_theme.dart';
import '../services/web_file_saver.dart';
import 'android_inapp_pdf_viewer.dart';
import 'web_iframe_viewer.dart';

/// نافذة المعاينة التفاعلية الذكية المدمجة بملء الشاشة
/// تعرض ملفات الـ PDF، الصور، والمستندات داخل التطبيق مباشرة دون تنزيل قسري ودون مغادرة التطبيق
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
  bool _useFallback = false;
  int _retryKey = 0;
  bool _isDownloading = false;

  String get _currentImageUrl {
    final raw = widget.rawUrl.trim();
    final resolved = AppConstants.resolveImageUrl(raw);
    if (!_useFallback) {
      return resolved;
    }
    if (resolved.contains('/api/proxy?url=')) {
      return raw;
    } else {
      final enc = Uri.encodeComponent(raw);
      return 'https://mohadarati.vercel.app/api/proxy?url=$enc';
    }
  }

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

    // 1. ملفات PDF في بيئة الويب: عارض PDF.js المدمج المحلي بدون فتح تبويب خارجي
    if (_isPdf) {
      final proxied = kIsWeb
          ? AppConstants.resolveImageUrl(clean)
          : 'https://mohadarati.vercel.app/api/proxy?url=${Uri.encodeComponent(clean)}';
      final base = kIsWeb ? 'pdf_viewer.html' : 'https://mohadarati.vercel.app/pdf_viewer.html';
      return '$base?file=${Uri.encodeComponent(proxied)}';
    }

    // 2. صور
    if (_isImage) {
      return AppConstants.resolveImageUrl(clean);
    }

    // 3. روابط Google Drive
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

    return clean;
  }

  String get _downloadTargetUrl {
    if (widget.explicitDownloadUrl != null && widget.explicitDownloadUrl!.trim().isNotEmpty) {
      return widget.explicitDownloadUrl!.trim();
    }
    return widget.rawUrl.trim();
  }

  /// تنزيل الملف وحفظه مباشرة في الجهاز دون فتح أي متصفح خارجي
  Future<void> _handleDownloadInApp() async {
    if (_isDownloading) return;
    setState(() => _isDownloading = true);

    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      SnackBar(
        content: Text('جاري بدء تنزيل الملف في الخلفية... 📥', style: GoogleFonts.cairo()),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );

    try {
      final client = http.Client();
      final res = await client.get(Uri.parse(_downloadTargetUrl)).timeout(const Duration(minutes: 5));

      if (res.statusCode == 200 && res.bodyBytes.isNotEmpty) {
        final fname = widget.fileName ?? '${widget.title}.pdf';
        await saveFileInBrowser(res.bodyBytes, fname);

        if (mounted) {
          messenger.showSnackBar(
            SnackBar(
              content: Text(
                kIsWeb
                    ? 'تم تنزيل الملف بنجاح إلى ملفات جهازك 📥'
                    : 'تم حفظ الملف بنجاح في مجلد التنزيلات (Downloads/محاضراتي) 📥',
                style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
              ),
              backgroundColor: const Color(0xFF059669),
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 4),
            ),
          );
        }
      } else {
        throw Exception('رمز الاستجابة: ${res.statusCode}');
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('تعذر إكمال التنزيل: $e', style: GoogleFonts.cairo()),
            backgroundColor: AppTheme.danger,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isDownloading = false);
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
    final resolvedImageUrl = _currentImageUrl;

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E293B),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded, color: Colors.white, size: 26),
          tooltip: 'إغلاق',
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
              tooltip: 'تدوير',
              onPressed: _rotateImage,
            ),
            IconButton(
              icon: const Icon(Icons.restart_alt_rounded, color: Colors.white70, size: 20),
              tooltip: 'إعادة ضبط',
              onPressed: _resetZoom,
            ),
          ],

          // تنزيل الملف مباشرة داخل التطبيق دون أي متصفح
          IconButton(
            icon: _isDownloading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                  )
                : const Icon(Icons.download_rounded, color: Colors.white, size: 22),
            tooltip: 'تنزيل وحفظ في الجهاز',
            onPressed: _isDownloading ? null : _handleDownloadInApp,
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
              key: ValueKey('preview_img_${_retryKey}_$imageUrl'),
              fit: BoxFit.contain,
              loadingBuilder: (context, child, progress) {
                if (progress == null) return child;
                return const Center(
                  child: CircularProgressIndicator(color: AppTheme.primary, strokeWidth: 2.5),
                );
              },
              errorBuilder: (context, error, stackTrace) {
                if (!_useFallback) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) {
                      setState(() {
                        _useFallback = true;
                        _retryKey++;
                      });
                    }
                  });
                  return const Center(
                    child: CircularProgressIndicator(color: AppTheme.primary, strokeWidth: 2.5),
                  );
                }
                return _buildErrorState('تعذر فتح الملف');
              },
            ),
          ),
        ),
      ),
    );
  }

  /// عارض المستندات والـ PDF المدمج أصيلاً داخل التطبيق بدون أي متصفح خارجي
  Widget _buildDocumentViewer(String embedUrl) {
    if (kIsWeb) {
      return SizedBox.expand(
        child: buildWebIFrame(
          url: embedUrl,
          title: widget.title,
        ),
      );
    }

    if (_isPdf) {
      return AndroidInAppPdfViewer(
        url: widget.rawUrl,
        title: widget.title,
      );
    }

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 420),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFF334155)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.4),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  color: AppTheme.accent.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                  border: Border.all(color: AppTheme.accent.withValues(alpha: 0.4), width: 2),
                ),
                child: const Icon(
                  Icons.description_rounded,
                  color: AppTheme.accent,
                  size: 38,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                widget.title,
                textAlign: TextAlign.center,
                style: GoogleFonts.cairo(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  height: 1.3,
                ),
              ),
              if (widget.subtitle != null && widget.subtitle!.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  widget.subtitle!,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.cairo(
                    color: const Color(0xFF94A3B8),
                    fontSize: 12,
                  ),
                ),
              ],
              const SizedBox(height: 24),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _handleDownloadInApp,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.download_rounded, size: 20),
                  label: Text(
                    'تنزيل الملف في جهازك',
                    style: GoogleFonts.cairo(fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
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
              onPressed: () => setState(() {
                _useFallback = false;
                _retryKey++;
              }),
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
