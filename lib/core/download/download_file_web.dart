import 'dart:js_interop';

import 'package:web/web.dart' as web;

Future<bool> downloadTextFile({
  required String filename,
  required String contents,
  required String mimeType,
}) async {
  final blob = web.Blob(
    <JSAny>[contents.toJS].toJS,
    web.BlobPropertyBag(type: mimeType),
  );
  final url = web.URL.createObjectURL(blob);
  final anchor = web.HTMLAnchorElement()
    ..href = url
    ..download = filename;
  anchor.click();
  web.URL.revokeObjectURL(url);
  return true;
}
