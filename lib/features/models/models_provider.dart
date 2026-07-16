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

final sessionModeProvider = StateProvider<String>((ref) => 'build');

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
    if (agent == 'plan') return 'plan';
    if (agent == 'build') return 'build';
  }
  return null;
});
