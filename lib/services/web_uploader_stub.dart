import 'dart:async';
import 'dart:typed_data';
import 'package:http/http.dart' as http;

class ProgressMultipartRequest extends http.MultipartRequest {
  final void Function(int bytesSent, int totalBytes)? onProgress;

  ProgressMultipartRequest(
    String method,
    Uri url, {
    this.onProgress,
  }) : super(method, url);

  @override
  http.ByteStream finalize() {
    final byteStream = super.finalize();
    final total = contentLength;
    int bytesSent = 0;

    final transformer = StreamTransformer<List<int>, List<int>>.fromHandlers(
      handleData: (List<int> data, EventSink<List<int>> sink) {
        bytesSent += data.length;
        if (onProgress != null && total > 0) {
          onProgress!(bytesSent, total);
        }
        sink.add(data);
      },
      handleError: (error, stack, sink) => sink.addError(error, stack),
      handleDone: (sink) => sink.close(),
    );

    return http.ByteStream(byteStream.transform(transformer));
  }
}

Future<http.Response> postMultipartWithProgress({
  required Uri uri,
  required Map<String, String> fields,
  required Uint8List fileBytes,
  required String fileField,
  required String fileName,
  required void Function(int bytesSent, int totalBytes)? onProgress,
  Duration timeout = const Duration(minutes: 30),
}) async {
  final request = ProgressMultipartRequest('POST', uri, onProgress: onProgress);
  request.fields.addAll(fields);
  request.files.add(
    http.MultipartFile.fromBytes(
      fileField,
      fileBytes,
      filename: fileName,
    ),
  );

  final streamedResponse = await request.send().timeout(timeout);
  return await http.Response.fromStream(streamedResponse);
}
