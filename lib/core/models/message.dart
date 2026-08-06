class MessageInfo {
  const MessageInfo({
    required this.id,
    required this.role,
    this.sessionID,
    this.modelID,
    this.providerID,
    this.agent,
    this.mode,
    this.time,
    this.error,
  });

  final String id;
  final String role;
  final String? sessionID;
  final String? modelID;
  final String? providerID;
  final String? agent;
  final String? mode;
  final Map<String, dynamic>? time;
  final Map<String, dynamic>? error;

  int? get timeCreated {
    final t = time?['created'];
    return t is int ? t : null;
  }

  int? get timeCompleted {
    final t = time?['completed'];
    return t is int ? t : null;
  }

  String? get errorMessage {
    if (error == null) return null;
    final data = error!['data'];
    if (data is Map<String, dynamic>) {
      return data['message'] as String?;
    }
    return error!['name']?.toString();
  }

  bool get hasRetryableError {
    if (error == null) return false;
    return error!['name']?.toString() == 'APIError';
  }

  factory MessageInfo.fromJson(Map<String, dynamic> json) {
    String? modelID = json['modelID'] as String?;
    String? providerID = json['providerID'] as String?;
    final modelObj = json['model'];
    if (modelObj is Map<String, dynamic>) {
      modelID ??= modelObj['modelID'] as String?;
      providerID ??= modelObj['providerID'] as String?;
    }
    final time = json['time'];
    final error = json['error'];
    return MessageInfo(
      id: (json['id'] ?? '').toString(),
      role: (json['role'] ?? 'assistant').toString(),
      sessionID: json['sessionID'] as String?,
      modelID: modelID,
      providerID: providerID,
      agent: json['agent'] as String?,
      mode: json['mode'] as String?,
      time: time is Map<String, dynamic> ? time : null,
      error: error is Map<String, dynamic> ? error : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'role': role,
        if (sessionID != null) 'sessionID': sessionID,
        if (modelID != null) 'modelID': modelID,
        if (providerID != null) 'providerID': providerID,
        if (agent != null) 'agent': agent,
        if (mode != null) 'mode': mode,
        if (time != null) 'time': time,
        if (error != null) 'error': error,
      };
}

class MessagePart {
  const MessagePart({
    required this.id,
    required this.type,
    this.text,
    this.toolName,
    this.state,
    this.raw = const {},
  });

  final String id;
  final String type;
  final String? text;
  final String? toolName;
  final String? state;
  final Map<String, dynamic> raw;

  factory MessagePart.fromJson(Map<String, dynamic> json) {
    final stateObj = json['state'];
    String? state;
    if (stateObj is Map<String, dynamic>) {
      state = stateObj['status'] as String?;
    } else if (stateObj is String) {
      state = stateObj;
    }
    return MessagePart(
      id: (json['id'] ?? json['partID'] ?? '').toString(),
      type: (json['type'] ?? 'unknown').toString(),
      text: json['text'] as String?,
      toolName: json['tool'] as String? ?? json['toolName'] as String?,
      state: state,
      raw: json,
    );
  }

  Map<String, dynamic> toJson() => raw;
}

class MessageWithParts {
  MessageWithParts({required this.info, required this.parts});

  final MessageInfo info;
  final List<MessagePart> parts;

  factory MessageWithParts.fromJson(Map<String, dynamic> json) {
    final partsJson = (json['parts'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(MessagePart.fromJson)
        .toList();
    return MessageWithParts(
      info: MessageInfo.fromJson(json['info'] as Map<String, dynamic>),
      parts: partsJson,
    );
  }

  Map<String, dynamic> toJson() => {
        'info': info.toJson(),
        'parts': parts.map((p) => p.toJson()).toList(),
      };
}
