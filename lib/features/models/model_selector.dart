import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../core/models/provider.dart';
import '../../shared/widgets/sheet_keyboard_padding.dart';
import 'models_provider.dart';

class ModelSelectorBar extends ConsumerWidget {
  const ModelSelectorBar({super.key, this.sessionId});

  final String? sessionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedModel = ref.watch(selectedModelProvider);
    final selectedAgent = ref.watch(selectedAgentProvider);
    final defaultAgent = ref.watch(defaultAgentProvider);
    final currentModel =
        sessionId != null ? ref.watch(currentModelProvider(sessionId!)) : null;

    final modelLabel =
        selectedModel?.modelID ?? currentModel ?? 'Default model';
    final agentLabel = selectedAgent ?? defaultAgent ?? 'Default agent';

    return Row(
      children: [
        Expanded(
          child: OutlineButton(
            size: ButtonSize.small,
            onPressed: () => _openModelPicker(context, ref),
            child: Row(
              children: [
                const Icon(LucideIcons.cpu, size: 14),
                const Gap(6),
                Expanded(
                  child: Text(
                    modelLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (selectedModel == null && currentModel != null)
                  const Icon(LucideIcons.radio, size: 12).iconMutedForeground,
              ],
            ),
          ),
        ),
        const Gap(8),
        Expanded(
          child: OutlineButton(
            size: ButtonSize.small,
            onPressed: () => _openAgentPicker(context, ref),
            child: Row(
              children: [
                const Icon(LucideIcons.bot, size: 14),
                const Gap(6),
                Expanded(
                  child: Text(
                    agentLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _openModelPicker(BuildContext context, WidgetRef ref) {
    FocusManager.instance.primaryFocus?.unfocus();
    openSheetOverlay(
      context: context,
      position: OverlayPosition.bottom,
      builder: (context) {
        return SheetKeyboardPadding(
          child: Consumer(
            builder: (context, ref, _) {
              final providersAsync = ref.watch(providersProvider);
              final selectedModel = ref.watch(selectedModelProvider);
              return SafeArea(
                child: Container(
                  padding: const EdgeInsets.all(16),
                  constraints: const BoxConstraints(maxHeight: 540),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text('Select model').h4,
                      const Gap(12),
                      Flexible(
                        child: providersAsync.when(
                          loading: () =>
                              const Center(child: CircularProgressIndicator()),
                          error: (e, _) => Text('$e').muted,
                          data: (providers) => _ModelPickerList(
                            providers: providers,
                            selectedModel: selectedModel,
                            onSelect: (selection) {
                              ref.read(selectedModelProvider.notifier).state =
                                  selection;
                              closeSheet(context);
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  void _openAgentPicker(BuildContext context, WidgetRef ref) {
    FocusManager.instance.primaryFocus?.unfocus();
    openSheetOverlay(
      context: context,
      position: OverlayPosition.bottom,
      builder: (context) {
        return SheetKeyboardPadding(
          child: Consumer(
            builder: (context, ref, _) {
              final selectedAgent = ref.watch(selectedAgentProvider);
              final defaultAgent = ref.watch(defaultAgentProvider);
              final agentsAsync = ref.watch(primaryAgentsProvider);
              final effectiveAgent = selectedAgent ?? defaultAgent;
              return SafeArea(
                child: Container(
                  padding: const EdgeInsets.all(16),
                  constraints: const BoxConstraints(maxHeight: 480),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text('Select agent').h4,
                      const Gap(12),
                      Flexible(
                        child: agentsAsync.when(
                          loading: () =>
                              const Center(child: CircularProgressIndicator()),
                          error: (e, _) => Text('$e').muted,
                          data: (agents) {
                            if (agents.isEmpty) {
                              return const Text('No agents available').muted;
                            }
                            return ListView(
                              shrinkWrap: true,
                              children: [
                                if (selectedAgent != null)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 4),
                                    child: GhostButton(
                                      alignment: Alignment.centerLeft,
                                      onPressed: () {
                                        ref
                                            .read(
                                                selectedAgentProvider.notifier)
                                            .state = null;
                                        closeSheet(context);
                                      },
                                      child: const Text('Reset to default'),
                                    ),
                                  ),
                                for (final agent in agents)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 4),
                                    child: GhostButton(
                                      alignment: Alignment.centerLeft,
                                      onPressed: () {
                                        ref
                                            .read(
                                                selectedAgentProvider.notifier)
                                            .state = agent.name;
                                        closeSheet(context);
                                      },
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(agent.name),
                                                if (agent.description != null &&
                                                    agent.description!
                                                        .isNotEmpty)
                                                  Text(agent.description!)
                                                      .muted,
                                              ],
                                            ),
                                          ),
                                          if (effectiveAgent == agent.name)
                                            const Icon(LucideIcons.check,
                                                size: 16),
                                        ],
                                      ),
                                    ),
                                  ),
                              ],
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _ModelPickerList extends StatefulWidget {
  const _ModelPickerList({
    required this.providers,
    required this.selectedModel,
    required this.onSelect,
  });

  final List<ProviderInfo> providers;
  final ModelSelection? selectedModel;
  final ValueChanged<ModelSelection> onSelect;

  @override
  State<_ModelPickerList> createState() => _ModelPickerListState();
}

class _ModelPickerListState extends State<_ModelPickerList> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final q = _query.toLowerCase();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _searchController,
          placeholder: const Text('Search models...'),
          border: Border.all(color: Colors.transparent),
          features: const [
            InputFeature.leading(Icon(LucideIcons.search, size: 16)),
          ],
          onChanged: (value) => setState(() => _query = value.trim()),
        ),
        const Gap(8),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final provider in widget.providers) ...[
                if (_providerHasMatch(provider, q)) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Text(provider.name).muted.small.semiBold,
                  ),
                  for (final model in provider.models)
                    if (_modelMatches(model, q))
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: GhostButton(
                          alignment: Alignment.centerLeft,
                          onPressed: () => widget.onSelect(
                            ModelSelection(
                              providerID: provider.id,
                              modelID: model.id,
                            ),
                          ),
                          child: Row(
                            children: [
                              Expanded(child: Text(model.name)),
                              if (widget.selectedModel?.providerID ==
                                      provider.id &&
                                  widget.selectedModel?.modelID == model.id)
                                const Icon(LucideIcons.check, size: 16),
                            ],
                          ),
                        ),
                      ),
                ],
              ],
            ],
          ),
        ),
      ],
    );
  }

  bool _providerHasMatch(ProviderInfo provider, String q) {
    if (q.isEmpty) return true;
    if (provider.name.toLowerCase().contains(q)) return true;
    return provider.models.any((m) => _modelMatches(m, q));
  }

  bool _modelMatches(ModelInfo model, String q) {
    if (q.isEmpty) return true;
    return model.name.toLowerCase().contains(q) ||
        model.id.toLowerCase().contains(q);
  }
}
