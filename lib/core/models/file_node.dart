class FileNode {
  const FileNode({
    required this.name,
    required this.path,
    required this.isDirectory,
  });

  final String name;
  final String path;
  final bool isDirectory;

  factory FileNode.fromJson(Map<String, dynamic> json) {
    final type = (json['type'] ?? '').toString();
    final path = (json['path'] ?? json['absolute'] ?? '').toString();
    return FileNode(
      name: (json['name'] ?? path.split('/').last).toString(),
      path: path,
      isDirectory: type == 'directory' || (json['directory'] == true),
    );
  }
}

class FileContent {
  const FileContent({
    required this.content,
    this.type,
    this.isBinary = false,
    this.encoding,
    this.mimeType,
  });

  final String content;
  final String? type;
  final bool isBinary;
  final String? encoding;
  final String? mimeType;

  bool get isBase64Encoded => encoding == 'base64';

  factory FileContent.fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String?;
    return FileContent(
      content: (json['content'] ?? '').toString(),
      type: type,
      isBinary: type == 'binary' || (json['isBinary'] as bool? ?? false),
      encoding: json['encoding'] as String?,
      mimeType: json['mimeType'] as String?,
    );
  }
}

class FileDiff {
  const FileDiff({
    required this.file,
    required this.patch,
    this.before,
    this.after,
    this.additions = 0,
    this.deletions = 0,
    this.status,
  });

  final String file;
  final String patch;
  final String? before;
  final String? after;
  final int additions;
  final int deletions;
  final String? status;

  String get path => file;

  String get displayPatch {
    if (patch.isNotEmpty) return patch;
    if (before != null || after != null) {
      return _unifiedDiff(before ?? '', after ?? '', file);
    }
    return '';
  }

  factory FileDiff.fromJson(Map<String, dynamic> json) {
    final file = (json['file'] ?? json['path'] ?? '').toString();
    final before = json['before'];
    final after = json['after'];
    return FileDiff(
      file: file,
      patch: (json['patch'] ?? json['diff'] ?? '').toString(),
      before: before is String ? before : null,
      after: after is String ? after : null,
      additions: json['additions'] is int ? json['additions'] as int : 0,
      deletions: json['deletions'] is int ? json['deletions'] as int : 0,
      status: json['status'] is String ? json['status'] as String : null,
    );
  }
}

String _unifiedDiff(String before, String after, String path) {
  final a = before.split('\n');
  if (a.isNotEmpty && a.last.isEmpty) a.removeLast();
  final b = after.split('\n');
  if (b.isNotEmpty && b.last.isEmpty) b.removeLast();
  final diff = <String>[];
  diff.add('--- a/$path');
  diff.add('+++ b/$path');
  final maxLen = a.length > b.length ? a.length : b.length;
  var i = 0;
  while (i < maxLen) {
    final av = i < a.length ? a[i] : null;
    final bv = i < b.length ? b[i] : null;
    if (av != null && bv != null) {
      if (av == bv) {
        diff.add(' $av');
      } else {
        diff.add('-$av');
        diff.add('+$bv');
      }
    } else if (av != null) {
      diff.add('-$av');
    } else if (bv != null) {
      diff.add('+$bv');
    }
    i++;
  }
  return diff.join('\n');
}
