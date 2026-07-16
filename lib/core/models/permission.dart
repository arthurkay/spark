class PermissionRequest {
  const PermissionRequest({
    required this.id,
    required this.sessionID,
    this.title,
    this.type,
    this.metadata = const {},
  });

  final String id;
  final String sessionID;
  final String? title;
  final String? type;
  final Map<String, dynamic> metadata;

  factory PermissionRequest.fromJson(Map<String, dynamic> json) {
    final data = json['data'] is Map<String, dynamic>
        ? json['data'] as Map<String, dynamic>
        : json;
    final id = (data['id'] ?? data['permissionID'] ?? '').toString();
    final permission = data['permission'] as String?;
    final title = (data['title'] as String?) ?? permission;
    return PermissionRequest(
      id: id,
      sessionID: (data['sessionID'] ?? '').toString(),
      title: title,
      type: (data['type'] as String?) ?? permission,
      metadata: data['metadata'] as Map<String, dynamic>? ?? const {},
    );
  }
}
