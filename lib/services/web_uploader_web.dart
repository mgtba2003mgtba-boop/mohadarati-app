// ignore: avoid_web_libraries_in_flutter
import 'dart:async';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:typed_data';
import 'package:http/http.dart' as http;

Future<http.Response> postMultipartWithProgress({
  required Uri uri,
  required Map<String, String> fields,
  required Uint8List fileBytes,
  required String fileField,
  required String fileName,
  required void Function(int bytesSent, int totalBytes)? onProgress,
  Duration timeout = const Duration(minutes: 30),
}) async {
  final completer = Completer<http.Response>();
  final xhr = html.HttpRequest();

  xhr.open('POST', uri.toString());
  xhr.timeout = timeout.inMilliseconds;

  final formData = html.FormData();
  fields.forEach((k, v) => formData.append(k, v));
  final blob = html.Blob([fileBytes]);
  formData.appendBlob(fileField, blob, fileName);

  xhr.upload.onProgress.listen((html.ProgressEvent e) {
    if (e.lengthComputable && e.total != null && e.total! > 0) {
      onProgress?.call(e.loaded ?? 0, e.total!);
    }
  });

  xhr.onLoad.listen((_) {
    final status = xhr.status ?? 200;
    final headers = <String, String>{};
    final rawHeaders = xhr.getAllResponseHeaders();
    for (final line in rawHeaders.split('\n')) {
      final idx = line.indexOf(':');
      if (idx > 0) {
        headers[line.substring(0, idx).trim().toLowerCase()] =
            line.substring(idx + 1).trim();
      }
    }
    completer.complete(
      http.Response(xhr.responseText ?? '', status, headers: headers),
    );
  });

  xhr.onError.listen((e) {
    if (!completer.isCompleted) {
      completer.completeError(Exception('Network error during upload'));
    }
  });

  xhr.onTimeout.listen((_) {
    if (!completer.isCompleted) {
      completer.completeError(TimeoutException('Upload timed out'));
    }
  });

  xhr.send(formData);
  return completer.future;
}
