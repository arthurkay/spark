import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../shared/debouncer.dart';
import '../../shared/haptics.dart';
import '../../core/models/provider.dart';
import '../../shared/widgets/sheet_keyboard_padding.dart';
import 'models_provider.dart';

void openModelPicker({
  required BuildContext context,
  required WidgetRef ref,
  String? sessionId,
}) {
  FocusManager.instance.primaryFocus?.unfocus();
  openSheetOverlay(
    context: context,
    position: OverlayPosition.bottom,
    builder: (context) {
      return SheetKeyboardPadding(
        child: Consumer(
          builder: (context, ref, _) {
            final providersAsync = ref.watch(providersProvider);
            final selectedModel = sessionId != null
                ? ref.watch(selectedModelProvider(sessionId))
                : null;
            final currentSelection = sessionId != null
                ? ref.watch(currentModelSelectionProvider(sessionId))
                : null;
            final effectiveSelected = selectedModel ?? currentSelection;
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
                          selectedModel: effectiveSelected,
                          onSelect: (selection) {
                            setSelectedModel(ref, selection);
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

void openAgentPicker({required BuildContext context, required WidgetRef ref}) {
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
                                                selectedAgentProvider.notifier,
                                              )
                                              .state =
                                          null;
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
                                          .read(selectedAgentProvider.notifier)
                                          .state = agent
                                          .name;
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
                                                  agent.description!.isNotEmpty)
                                                Text(agent.description!).muted,
                                            ],
                                          ),
                                        ),
                                        if (effectiveAgent == agent.name)
                                          const Icon(
                                            LucideIcons.check,
                                            size: 16,
                                          ),
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
  final _searchDebouncer = Debouncer();
  String _query = '';
  String? _expandedProviderId;

  @override
  void initState() {
    super.initState();
    if (widget.selectedModel != null) {
      _expandedProviderId = widget.selectedModel!.providerID;
    }
  }

  @override
  void didUpdateWidget(covariant _ModelPickerList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedModel != null &&
        widget.selectedModel!.providerID != _expandedProviderId) {
      _expandedProviderId = widget.selectedModel!.providerID;
    }
  }

  @override
  void dispose() {
    _searchDebouncer.dispose();
    _searchController.dispose();
    super.dispose();
  }

  bool _modelMatches(ModelInfo model, String q) {
    if (q.isEmpty) return true;
    return model.name.toLowerCase().contains(q) ||
        model.id.toLowerCase().contains(q);
  }

  bool _providerHasMatch(ProviderInfo provider, String q) {
    if (q.isEmpty) return true;
    if (provider.name.toLowerCase().contains(q)) return true;
    return provider.models.any((m) => _modelMatches(m, q));
  }

  @override
  Widget build(BuildContext context) {
    final q = _query.toLowerCase();
    final searching = q.isNotEmpty;
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
          onChanged: (value) => _searchDebouncer.run(() {
            if (!mounted) return;
            setState(() => _query = value.trim());
          }),
        ),
        const Gap(8),
        Flexible(
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: _visibleProviderCount(q, searching),
            itemBuilder: (context, index) {
              return _buildProviderTile(index, q, searching);
            },
          ),
        ),
      ],
    );
  }

  int _visibleProviderCount(String q, bool searching) {
    if (searching) {
      return widget.providers.where((p) => _providerHasMatch(p, q)).length;
    }
    return widget.providers.length;
  }

  Widget _buildProviderTile(int index, String q, bool searching) {
    final provider = searching
        ? widget.providers
              .where((p) => _providerHasMatch(p, q))
              .elementAt(index)
        : widget.providers[index];
    final expanded = _expandedProviderId == provider.id;
    final models = searching
        ? provider.models.where((m) => _modelMatches(m, q)).toList()
        : provider.models;
    final hasModels = models.isNotEmpty;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GhostButton(
          alignment: Alignment.centerLeft,
          onPressed: hasModels
              ? () {
                  Haptics.tap();
                  setState(() {
                    _expandedProviderId = expanded ? null : provider.id;
                  });
                }
              : null,
          child: Row(
            children: [
              Expanded(child: Text(provider.name).semiBold),
              if (hasModels)
                Icon(
                  expanded ? LucideIcons.chevronUp : LucideIcons.chevronDown,
                  size: 16,
                ),
            ],
          ),
        ),
        if (expanded && hasModels)
          Padding(
            padding: const EdgeInsets.only(left: 8, top: 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final model in models) _buildModelTile(provider, model),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildModelTile(ProviderInfo provider, ModelInfo model) {
    final selected =
        widget.selectedModel?.providerID == provider.id &&
        widget.selectedModel?.modelID == model.id;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: GhostButton(
        alignment: Alignment.centerLeft,
        onPressed: () {
          Haptics.selection();
          widget.onSelect(
            ModelSelection(providerID: provider.id, modelID: model.id),
          );
        },
        child: Row(
          children: [
            Expanded(child: Text(model.name)),
            if (selected) const Icon(LucideIcons.check, size: 16),
          ],
        ),
      ),
    );
  }
}
