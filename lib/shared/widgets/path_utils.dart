String compactPath(String path, {int tailSegments = 2}) {
  final trimmed = path.trim();
  if (trimmed.isEmpty) return '';
  final segments = trimmed.split('/').where((s) => s.isNotEmpty).toList();
  if (segments.length <= tailSegments + 1) return trimmed;
  final tail = segments.skip(segments.length - tailSegments).join('/');
  return '…/$tail';
}
