import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../core/api/providers.dart';
import '../../core/models/provider.dart';
import '../chat/chat_provider.dart';

final providersProvider = FutureProvider<List<ProviderInfo>>((ref) async {
  final client = ref.watch(opencodeClientProvider);
  if (client == null) return [];
  return client.listProviders();
});

final agentsProvider = FutureProvider<List<Agent>>((ref) async {
  final client = ref.watch(opencodeClientProvider);
  if (client == null) return [];
  return client.listAgents();
});

final selectedModelProvider = StateProvider<ModelSelection?>((ref) => null);
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

final currentModeProvider = Provider.family<String?, String>((ref, sessionId) {
  final controller = ref.watch(chatControllerProvider(sessionId));
  final messages = controller.state.messages;
  for (final message in messages.reversed) {
    final agent = message.info.agent;
    if (agent != null && agent.isNotEmpty) return agent;
  }
  return null;
});
