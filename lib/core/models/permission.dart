import 'package:shadcn_flutter/shadcn_flutter.dart';

class PermissionRequest {
  const PermissionRequest({
    required this.id,
    required this.sessionID,
    this.title,
    this.type,
    this.metadata = const {},
    this.callID,
    this.messageID,
    this.pattern,
  });

  final String id;
  final String sessionID;
  final String? title;
  final String? type;
  final Map<String, dynamic> metadata;
  final String? callID;
  final String? messageID;
  final List<String>? pattern;

  factory PermissionRequest.fromJson(Map<String, dynamic> json) {
    final data = json['data'] is Map<String, dynamic>
        ? json['data'] as Map<String, dynamic>
        : json;
    final id = (data['id'] ?? data['permissionID'] ?? '').toString();
    final permission = data['permission'] as String?;
    final title = (data['title'] as String?) ?? permission;
    final rawPattern = data['pattern'];
    final pattern = rawPattern is List
        ? rawPattern.map((e) => e.toString()).toList()
        : (rawPattern is String ? [rawPattern] : null);
    return PermissionRequest(
      id: id,
      sessionID: (data['sessionID'] ?? '').toString(),
      title: title,
      type: (data['type'] as String?) ?? permission,
      metadata: data['metadata'] as Map<String, dynamic>? ?? const {},
      callID: data['callID'] as String?,
      messageID: data['messageID'] as String?,
      pattern: pattern,
    );
  }

  factory PermissionRequest.fromProps(Map<String, dynamic> props) {
    return PermissionRequest.fromJson(props);
  }
}

IconData permissionIcon(String? type) {
  switch (type) {
    case 'bash':
      return LucideIcons.terminal;
    case 'edit':
      return LucideIcons.pencil;
    case 'question':
      return LucideIcons.circleHelp;
    case 'webfetch':
      return LucideIcons.globe;
    case 'websearch':
      return LucideIcons.search;
    case 'read':
      return LucideIcons.fileText;
    case 'glob':
      return LucideIcons.folderSearch;
    case 'grep':
      return LucideIcons.searchCode;
    case 'task':
      return LucideIcons.layers;
    case 'skill':
      return LucideIcons.puzzle;
    case 'lsp':
      return LucideIcons.braces;
    case 'external_directory':
      return LucideIcons.folderOpen;
    case 'doom_loop':
      return LucideIcons.refreshCw;
    default:
      return LucideIcons.shieldQuestion;
  }
}
