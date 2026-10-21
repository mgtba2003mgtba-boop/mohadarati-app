// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:typed_data';

void saveFileInBrowser(Uint8List bytes, String fileName) {
  try {
    final blob = html.Blob([bytes]);
    final url = html.Url.createObjectUrlFromBlob(blob);
    final anchor = html.AnchorElement(href: url)
      ..setAttribute('download', fileName)
      ..click();
    html.Url.revokeObjectUrl(url);
  } catch (e) {
    // ignore
  }
}

String? createBlobUrl(Uint8List bytes, [String? mimeType]) {
  try {
    final type = (mimeType != null && mimeType.isNotEmpty) ? mimeType : 'application/octet-stream';
    final blob = html.Blob([bytes], type);
    return html.Url.createObjectUrlFromBlob(blob);
  } catch (e) {
    return null;
  }
}

void revokeBlobUrl(String url) {
  try {
    html.Url.revokeObjectUrl(url);
  } catch (_) {}
}
