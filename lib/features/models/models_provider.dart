import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../core/api/opencode_client.dart';
import '../../core/api/providers.dart';
import '../../core/models/provider.dart';
import '../../core/storage/cache_service.dart';
import '../chat/chat_provider.dart';

final configProvidersProvider =
    FutureProvider<Map<String, dynamic>>((ref) async {
  final client = ref.watch(opencodeClientProvider);
  if (client == null) return {};
  try {
    final res = await client.configProvidersRaw();
    return res;
  } catch (_) {
    return {};
  }
});

final providersProvider = FutureProvider<List<ProviderInfo>>((ref) async {
  final client = ref.watch(opencodeClientProvider);
  if (client == null) return [];
  const cacheKey = 'providers.json';
  try {
    final providers = await client.listProviders();
    await CacheService.instance.write(cacheKey, {
      'items': providers.map((p) => p.toJson()).toList(),
    });
    return providers;
  } on OpencodeApiException catch (_) {
    final cached = await CacheService.instance.read(cacheKey);
    if (cached != null) {
      final items = cached['items'] as List<dynamic>? ?? [];
      return items
          .whereType<Map<String, dynamic>>()
          .map(ProviderInfo.fromJson)
          .toList();
    }
    return [];
  }
});

final agentsProvider = FutureProvider<List<Agent>>((ref) async {
  final client = ref.watch(opencodeClientProvider);
  if (client == null) return [];
  const cacheKey = 'agents.json';
  try {
    final agents = await client.listAgents();
    await CacheService.instance.write(cacheKey, {
      'items': agents.map((a) => a.toJson()).toList(),
    });
    return agents;
  } on OpencodeApiException catch (_) {
    final cached = await CacheService.instance.read(cacheKey);
    if (cached != null) {
      final items = cached['items'] as List<dynamic>? ?? [];
      return items
          .whereType<Map<String, dynamic>>()
          .map(Agent.fromJson)
          .toList();
    }
    return [];
  }
});

final _selectedModelOverride = StateProvider<ModelSelection?>((ref) => null);

final selectedModelProvider =
    Provider.family<ModelSelection?, String>((ref, sessionId) {
  final override = ref.watch(_selectedModelOverride);
  if (override != null) return override;
  final fromLastMessage = ref.watch(currentModelSelectionProvider(sessionId));
  if (fromLastMessage != null) return fromLastMessage;
  final defaultsAsync = ref.watch(configProvidersProvider);
  return defaultsAsync.whenOrNull(
    data: (config) {
      final defaults = config['default'] as Map<String, dynamic>?;
      if (defaults == null || defaults.isEmpty) return null;
      final entry = defaults.entries.first;
      final providerID = entry.key;
      final modelID = entry.value?.toString();
      if (modelID == null || modelID.isEmpty) return null;
      return ModelSelection(providerID: providerID, modelID: modelID);
    },
  );
});

void setSelectedModel(WidgetRef ref, ModelSelection? selection) {
  ref.read(_selectedModelOverride.notifier).state = selection;
}

final selectedAgentProvider = StateProvider<String?>((ref) => null);

final serverConfigProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final client = ref.watch(opencodeClientProvider);
  if (client == null) return {};
  return client.getConfig();
});

final defaultAgentProvider = Provider<String?>((ref) {
  final configAsync = ref.watch(serverConfigProvider);
  return configAsync.whenOrNull(
    data: (config) => (config['default_agent'] as String?) ?? 'build',
  );
});

final primaryAgentsProvider = Provider<AsyncValue<List<Agent>>>((ref) {
  final agentsAsync = ref.watch(agentsProvider);
  return agentsAsync.whenData(
    (agents) => agents
        .where((a) => (a.mode == 'primary' || a.mode == 'all') && !a.hidden)
        .toList(),
  );
});

final currentModelProvider = Provider.family<String?, String>((ref, sessionId) {
  final controller = ref.watch(chatControllerProvider(sessionId));
  final messages = controller.state.messages;
  for (final message in messages.reversed) {
    final modelID = message.info.modelID;
    if (modelID != null && modelID.isNotEmpty) {
      final provider = message.info.providerID;
      return provider != null && provider.isNotEmpty
          ? '$provider/$modelID'
          : modelID;
    }
  }
  return null;
});

final currentModelSelectionProvider =
    Provider.family<ModelSelection?, String>((ref, sessionId) {
  final controller = ref.watch(chatControllerProvider(sessionId));
  final messages = controller.state.messages;
  for (final message in messages.reversed) {
    final modelID = message.info.modelID;
    if (modelID != null && modelID.isNotEmpty) {
      final providerID = message.info.providerID;
      if (providerID != null && providerID.isNotEmpty) {
        return ModelSelection(providerID: providerID, modelID: modelID);
      }
      return ModelSelection(providerID: '', modelID: modelID);
    }
  }
  return null;
});

final currentModeProvider = Provider.family<String?, String>((ref, sessionId) {
  final controller = ref.watch(chatControllerProvider(sessionId));
  final messages = controller.state.messages;
  for (final message in messages.reversed) {
    final agent = message.info.agent;
    if (agent != null && agent.isNotEmpty) return agent;
  }
  return null;
});
