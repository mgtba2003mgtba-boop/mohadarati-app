// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
// ignore: avoid_web_libraries_in_flutter
import 'dart:ui_web' as ui_web;
import 'package:flutter/material.dart';

int _nextViewId = 0;

/// بيئة الويب - إنشاء عارض مستندات أو فيديو مدمج
Widget createWebIFrameWidget({
  required String url,
  required String title,
}) {
  final viewType = 'app-iframe-view-${_nextViewId++}';

  ui_web.platformViewRegistry.registerViewFactory(
    viewType,
    (int viewId) {
      final iframe = html.IFrameElement()
        ..src = url
        ..title = title
        ..style.border = 'none'
        ..style.width = '100%'
        ..style.height = '100%'
        ..allowFullscreen = true;
      return iframe;
    },
  );

  return HtmlElementView(viewType: viewType);
}
