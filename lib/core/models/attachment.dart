import 'dart:typed_data';

class Attachment {
  const Attachment({
    required this.name,
    required this.path,
    required this.mime,
    required this.bytes,
  });

  final String name;
  final String path;
  final String mime;
  final Uint8List bytes;

  bool get isImage => mime.startsWith('image/');

  String get sizeLabel {
    final bytes = this.bytes.length;
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
