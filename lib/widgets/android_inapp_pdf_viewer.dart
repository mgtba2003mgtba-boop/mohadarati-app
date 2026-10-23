import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import '../core/theme/app_theme.dart';
import '../services/native_pdf_service.dart';

class AndroidInAppPdfViewer extends StatefulWidget {
  final String url;
  final String title;

  const AndroidInAppPdfViewer({
    super.key,
    required this.url,
    required this.title,
  });

  @override
  State<AndroidInAppPdfViewer> createState() => _AndroidInAppPdfViewerState();
}

class _AndroidInAppPdfViewerState extends State<AndroidInAppPdfViewer> {
  bool _isLoading = true;
  String _loadingStatus = 'جاري الاتصال وتحميل المستند...';
  double _downloadProgress = 0.0;
  String? _errorMessage;

  int _pageCount = 0;
  final Map<int, Uint8List> _renderedPagesCache = {};
  String? _cachedFilePath;

  @override
  void initState() {
    super.initState();
    _loadAndPreparePdf();
  }

  Future<void> _loadAndPreparePdf() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _loadingStatus = 'جاري تجهيز المستند...';
      _downloadProgress = 0.05;
    });

    try {
      // 1. تحديد مسار الكاش المحلي
      const updaterChannel = MethodChannel('iq.edu.nust.mohadarati/updater');
      final cacheDirStr = await updaterChannel.invokeMethod<String>('getCacheDir');
      final cacheDir = cacheDirStr != null ? Directory(cacheDirStr) : Directory.systemTemp;

      final urlHash = widget.url.hashCode.abs();
      final localFile = File('${cacheDir.path}/doc_$urlHash.pdf');

      // 2. فحص إن كان الملف محملاً مسبقاً في الكاش المحلي (Offline Cache)
      if (await localFile.exists() && (await localFile.length()) > 1024) {
        _cachedFilePath = localFile.path;
      } else {
        setState(() {
          _loadingStatus = 'جاري تنزيل صفحات المحاضرة...';
          _downloadProgress = 0.2;
        });

        final client = http.Client();
        final request = http.Request('GET', Uri.parse(widget.url));
        final streamedResponse = await client.send(request);

        final totalBytes = streamedResponse.contentLength ?? 0;
        int receivedBytes = 0;
        final List<int> bytes = [];

        await for (var chunk in streamedResponse.stream) {
          bytes.addAll(chunk);
          receivedBytes += chunk.length;
          if (totalBytes > 0) {
            final prog = (receivedBytes / totalBytes).clamp(0.2, 0.85);
            if (mounted) {
              setState(() {
                _downloadProgress = prog;
              });
            }
          }
        }

        if (bytes.isEmpty) {
          throw Exception('الملف فارغ أو تعذر الوصول إليه.');
        }

        await localFile.writeAsBytes(bytes);
        _cachedFilePath = localFile.path;
      }

      setState(() {
        _loadingStatus = 'جاري تصيير الصفحات...';
        _downloadProgress = 0.9;
      });

      // 3. فتح المستند عبر محرك الـ PDF الأصلي في الأندرويد
      final pages = await NativePdfService.instance.openPdf(_cachedFilePath!);
      if (pages <= 0) {
        throw Exception('تعذر قراءة صفحات المستند أو الملف غير صالح.');
      }

      if (mounted) {
        setState(() {
          _pageCount = pages;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  @override
  void dispose() {
    NativePdfService.instance.closePdf();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  shape: BoxShape.circle,
                  border: Border.all(color: AppTheme.accent.withValues(alpha: 0.3)),
                ),
                child: const Icon(Icons.picture_as_pdf_rounded, color: AppTheme.accent, size: 36),
              ),
              const SizedBox(height: 18),
              Text(
                _loadingStatus,
                textAlign: TextAlign.center,
                style: GoogleFonts.cairo(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: 200,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: _downloadProgress > 0 ? _downloadProgress : null,
                    backgroundColor: const Color(0xFF334155),
                    valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.accent),
                    minHeight: 5,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded, color: Color(0xFFEF4444), size: 48),
              const SizedBox(height: 12),
              Text(
                'تعذر فتح المحاضرة داخل التطبيق',
                style: GoogleFonts.cairo(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: GoogleFonts.cairo(color: const Color(0xFF94A3B8), fontSize: 12),
              ),
              const SizedBox(height: 18),
              ElevatedButton.icon(
                onPressed: _loadAndPreparePdf,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: Text('إعادة المحاولة', style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      );
    }

    return InteractiveViewer(
      minScale: 1.0,
      maxScale: 4.0,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
        itemCount: _pageCount,
        itemBuilder: (context, index) {
          return _buildPageCard(index);
        },
      ),
    );
  }

  Widget _buildPageCard(int pageIndex) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // شريط رقم الصفحة الأنيق
          Container(
            color: const Color(0xFF1E293B),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'صفحة ${pageIndex + 1} من $_pageCount',
                  style: GoogleFonts.cairo(
                    color: const Color(0xFF94A3B8),
                    fontSize: 10.5,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Icon(Icons.description_outlined, color: Color(0xFF64748B), size: 14),
              ],
            ),
          ),

          // صورة الصفحة المصيرة
          if (_renderedPagesCache.containsKey(pageIndex))
            Image.memory(
              _renderedPagesCache[pageIndex]!,
              fit: BoxFit.contain,
            )
          else
            FutureBuilder<Uint8List?>(
              future: NativePdfService.instance.renderPage(pageIndex, targetWidth: 1080),
              builder: (ctx, snap) {
                if (snap.connectionState == ConnectionState.done && snap.hasData && snap.data != null) {
                  _renderedPagesCache[pageIndex] = snap.data!;
                  return Image.memory(
                    snap.data!,
                    fit: BoxFit.contain,
                  );
                }
                return Container(
                  height: 380,
                  color: const Color(0xFFF1F5F9),
                  child: const Center(
                    child: CircularProgressIndicator(
                      color: AppTheme.primary,
                      strokeWidth: 2.2,
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}
