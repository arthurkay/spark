class ModelInfo {
  const ModelInfo({required this.id, required this.name});

  final String id;
  final String name;

  factory ModelInfo.fromJson(String id, Map<String, dynamic> json) {
    return ModelInfo(id: id, name: (json['name'] ?? id).toString());
  }
}

class ProviderInfo {
  const ProviderInfo({
    required this.id,
    required this.name,
    required this.models,
  });

  final String id;
  final String name;
  final List<ModelInfo> models;

  factory ProviderInfo.fromJson(Map<String, dynamic> json) {
    final modelsJson = json['models'] as Map<String, dynamic>? ?? {};
    final models = modelsJson.entries
        .map((e) => ModelInfo.fromJson(e.key, e.value as Map<String, dynamic>))
        .toList();
    return ProviderInfo(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? json['id'] ?? '').toString(),
      models: models,
    );
  }
}

class Agent {
  const Agent({
    required this.name,
    this.description,
    this.mode = 'primary',
    this.hidden = false,
  });

  final String name;
  final String? description;
  final String mode;
  final bool hidden;

  factory Agent.fromJson(Map<String, dynamic> json) {
    return Agent(
      name: (json['name'] ?? '').toString(),
      description: json['description'] as String?,
      mode: (json['mode'] ?? 'primary').toString(),
      hidden: json['hidden'] == true,
    );
  }
}

class ModelSelection {
  const ModelSelection({required this.providerID, required this.modelID});

  final String providerID;
  final String modelID;

  Map<String, String> toJson() => {
        'providerID': providerID,
        'modelID': modelID,
      };
}
