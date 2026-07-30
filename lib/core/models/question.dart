class QuestionOption {
  const QuestionOption({required this.label, this.description});

  final String label;
  final String? description;

  factory QuestionOption.fromJson(Map<String, dynamic> json) {
    return QuestionOption(
      label: (json['label'] as String?) ?? '',
      description: json['description'] as String?,
    );
  }
}

class QuestionInfo {
  const QuestionInfo({
    required this.question,
    this.header,
    this.options = const [],
    this.multiple = false,
    this.custom = false,
  });

  final String question;
  final String? header;
  final List<QuestionOption> options;
  final bool multiple;
  final bool custom;

  factory QuestionInfo.fromJson(Map<String, dynamic> json) {
    final opts = (json['options'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(QuestionOption.fromJson)
        .toList();
    return QuestionInfo(
      question: (json['question'] as String?) ?? '',
      header: json['header'] as String?,
      options: opts,
      multiple: json['multiple'] == true,
      custom: json['custom'] == true,
    );
  }
}

class QuestionRequest {
  const QuestionRequest({
    required this.id,
    required this.sessionID,
    required this.questions,
    this.messageID,
    this.callID,
    this.directory,
  });

  final String id;
  final String sessionID;
  final List<QuestionInfo> questions;
  final String? messageID;
  final String? callID;
  final String? directory;

  QuestionRequest copyWith({String? directory}) {
    return QuestionRequest(
      id: id,
      sessionID: sessionID,
      questions: questions,
      messageID: messageID,
      callID: callID,
      directory: directory ?? this.directory,
    );
  }

  factory QuestionRequest.fromJson(Map<String, dynamic> json) {
    final tool = json['tool'] is Map<String, dynamic>
        ? json['tool'] as Map<String, dynamic>
        : null;
    final questions = (json['questions'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(QuestionInfo.fromJson)
        .toList();
    return QuestionRequest(
      id: (json['id'] ?? '').toString(),
      sessionID: (json['sessionID'] ?? '').toString(),
      questions: questions,
      messageID: tool?['messageID'] as String?,
      callID: tool?['callID'] as String?,
      directory: json['directory'] as String?,
    );
  }

  String get key => messageID ?? callID ?? id;
}
