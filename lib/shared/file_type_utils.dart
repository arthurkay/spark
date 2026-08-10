bool isImageMime(String? mime) => mime != null && mime.startsWith('image/');

bool isSupportedImageExtension(String path) {
  final name = path.split('/').last.toLowerCase();
  return _imageExtensions.contains(name.split('.').last);
}

String? extensionFromPath(String path) {
  final name = path.split('/').last;
  final dot = name.lastIndexOf('.');
  if (dot < 0) return null;
  return name.substring(dot + 1).toLowerCase();
}

String? mimeFromExtension(String ext) {
  return _extensions[ext] ?? _extensions[ext.toLowerCase()];
}

const _imageExtensions = {
  'png',
  'jpg',
  'jpeg',
  'gif',
  'webp',
  'svg',
  'bmp',
  'ico',
};

const _extensions = <String, String>{
  'png': 'image/png',
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'gif': 'image/gif',
  'webp': 'image/webp',
  'svg': 'image/svg+xml',
  'bmp': 'image/bmp',
  'ico': 'image/x-icon',
  'pdf': 'application/pdf',
  'json': 'application/json',
  'txt': 'text/plain',
  'md': 'text/plain',
  'markdown': 'text/plain',
  'dart': 'text/plain',
  'js': 'text/plain',
  'ts': 'text/plain',
  'py': 'text/plain',
  'rb': 'text/plain',
  'go': 'text/plain',
  'rs': 'text/plain',
  'java': 'text/plain',
  'kt': 'text/plain',
  'swift': 'text/plain',
  'c': 'text/plain',
  'cpp': 'text/plain',
  'h': 'text/plain',
  'cs': 'text/plain',
  'sh': 'text/plain',
  'bash': 'text/plain',
  'zsh': 'text/plain',
  'yaml': 'text/plain',
  'yml': 'text/plain',
  'toml': 'text/plain',
  'xml': 'text/plain',
  'html': 'text/plain',
  'css': 'text/plain',
  'scss': 'text/plain',
  'sql': 'text/plain',
  'csv': 'text/plain',
};
