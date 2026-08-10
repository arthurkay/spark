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

void openAgentPicker({
  required BuildContext context,
  required WidgetRef ref,
}) {
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
                                          .read(selectedAgentProvider.notifier)
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
                                          .read(selectedAgentProvider.notifier)
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
                                                  agent.description!.isNotEmpty)
                                                Text(agent.description!).muted,
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

  @override
  void dispose() {
    _searchDebouncer.dispose();
    _searchController.dispose();
    super.dispose();
  }

  /// Flattened, filtered rows for the list. Building this first lets the list be
  /// lazy: the previous nested provider×model loops inside a
  /// `ListView(shrinkWrap: true)` constructed every row of every provider on
  /// each keystroke.
  List<_PickerRow> _rows(String q) {
    final rows = <_PickerRow>[];
    for (final provider in widget.providers) {
      if (!_providerHasMatch(provider, q)) continue;
      rows.add(_PickerRow.header(provider.name));
      for (final model in provider.models) {
        if (_modelMatches(model, q)) {
          rows.add(_PickerRow.model(provider.id, model));
        }
      }
    }
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    final q = _query.toLowerCase();
    final rows = _rows(q);
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
            itemCount: rows.length,
            itemBuilder: (context, index) {
              final row = rows[index];
              final model = row.model;
              if (model == null) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Text(row.label).muted.small.semiBold,
                );
              }
              final selected =
                  widget.selectedModel?.providerID == row.providerID &&
                      widget.selectedModel?.modelID == model.id;
              return Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: GhostButton(
                  alignment: Alignment.centerLeft,
                  onPressed: () {
                    Haptics.selection();
                    widget.onSelect(
                      ModelSelection(
                        providerID: row.providerID!,
                        modelID: model.id,
                      ),
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
            },
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

/// One row of the flattened model picker: either a provider header
/// ([model] == null) or a selectable model.
class _PickerRow {
  const _PickerRow.header(this.label)
      : providerID = null,
        model = null;

  const _PickerRow.model(this.providerID, this.model) : label = '';

  final String label;
  final String? providerID;
  final ModelInfo? model;
}
