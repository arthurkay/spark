import 'package:flutter/services.dart';
import 'package:re_editor/re_editor.dart';
import 'package:re_highlight/languages/all.dart' as langs;
import 'package:re_highlight/styles/atom-one-dark.dart' as dark;
import 'package:re_highlight/styles/atom-one-light.dart' as light;
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../shared/widgets/code_highlight_view.dart';

class EditorPane extends StatefulWidget {
  const EditorPane({
    super.key,
    required this.path,
    required this.initialContent,
    required this.onChanged,
    required this.onSave,
    this.isBinary = false,
    this.loading = false,
    this.error,
  });

  final String path;
  final String initialContent;
  final ValueChanged<String> onChanged;
  final VoidCallback onSave;
  final bool isBinary;
  final bool loading;
  final String? error;

  @override
  State<EditorPane> createState() => _EditorPaneState();
}

class _EditorPaneState extends State<EditorPane> {
  late final CodeLineEditingController _controller;
  late final CodeFindController _findController;

  @override
  void initState() {
    super.initState();
    _controller = CodeLineEditingController.fromText(widget.initialContent);
    _controller.addListener(_handleChanged);
    _findController = CodeFindController(_controller);
  }

  @override
  void dispose() {
    _controller.removeListener(_handleChanged);
    _findController.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _handleChanged() {
    widget.onChanged(_controller.text);
  }

  void _toggleFind() {
    if (_findController.value?.searching == true) {
      _findController.close();
    } else {
      _findController.findMode();
    }
  }

  PreferredSizeWidget _buildFindPanel(
    BuildContext context,
    CodeFindController controller,
    bool readonly,
  ) {
    final scheme = Theme.of(context).colorScheme;
    return PreferredSize(
      preferredSize: const Size.fromHeight(44),
      child: Container(
        margin: const EdgeInsets.only(right: 12, top: 8),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: scheme.card,
          border: Border.all(color: scheme.border),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: SizedBox(
                width: 220,
                child: TextField(
                  controller: controller.findInputController,
                  placeholder: const Text('Find'),
                  border: Border.all(color: Colors.transparent),
                ),
              ),
            ),
            ValueListenableBuilder<CodeFindValue?>(
              valueListenable: controller,
              builder: (context, value, _) {
                final result = value?.result;
                final pattern = controller.findInputController.text;
                final label = result == null || pattern.isEmpty
                    ? ''
                    : '${result.index + 1}/${result.matches.length}';
                return SizedBox(
                  width: 64,
                  child: Text(label, textAlign: TextAlign.center).xSmall.muted,
                );
              },
            ),
            IconButton.ghost(
              icon: const Icon(LucideIcons.chevronUp, size: 16),
              size: ButtonSize.small,
              onPressed: controller.previousMatch,
            ),
            IconButton.ghost(
              icon: const Icon(LucideIcons.chevronDown, size: 16),
              size: ButtonSize.small,
              onPressed: controller.nextMatch,
            ),
            IconButton.ghost(
              icon: const Icon(LucideIcons.x, size: 16),
              size: ButtonSize.small,
              onPressed: controller.close,
            ),
          ],
        ),
      ),
    );
  }

  CodeHighlightTheme? _codeTheme(BuildContext context) {
    final brightness = MediaQuery.platformBrightnessOf(context);
    final lang = CodeHighlightView.detectLanguage(null, widget.path);
    final themeMap = brightness == Brightness.dark
        ? dark.atomOneDarkTheme
        : light.atomOneLightTheme;
    if (lang == null || !langs.builtinAllLanguages.containsKey(lang)) {
      return CodeHighlightTheme(languages: const {}, theme: themeMap);
    }
    return CodeHighlightTheme(
      languages: {
        lang: CodeHighlightThemeMode(mode: langs.builtinAllLanguages[lang]!),
      },
      theme: themeMap,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (widget.error != null) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                LucideIcons.triangleAlert,
                size: 36,
              ).iconMutedForeground,
              const Gap(12),
              Text(widget.error!).muted.textCenter,
            ],
          ),
        ),
      );
    }
    if (widget.isBinary) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(LucideIcons.fileWarning, size: 36).iconMutedForeground,
            const Gap(12),
            const Text('Binary file — cannot be edited').muted,
          ],
        ),
      );
    }

    final scheme = Theme.of(context).colorScheme;
    final mono = CodeHighlightView.monoFamilies;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyF, control: true):
            _toggleFind,
        const SingleActivator(LogicalKeyboardKey.keyF, meta: true): _toggleFind,
      },
      child: CodeEditor(
        key: ValueKey(widget.path),
        controller: _controller,
        findController: _findController,
        findBuilder: _buildFindPanel,
        style: CodeEditorStyle(
          fontSize: 13,
          fontHeight: 1.5,
          fontFamily: mono.first,
          fontFamilyFallback: mono.skip(1).toList(),
          textColor: scheme.foreground,
          backgroundColor: scheme.background,
          selectionColor: scheme.primary.withValues(alpha: 0.28),
          cursorColor: scheme.primary,
          cursorLineColor: scheme.muted.withValues(alpha: 0.35),
          chunkIndicatorColor: scheme.mutedForeground,
          codeTheme: _codeTheme(context),
        ),
        padding: const EdgeInsets.fromLTRB(12, 10, 16, 24),
        wordWrap: false,
        autofocus: true,
        maxLengthSingleLineRendering: 20000,
        onChanged: (value) => widget.onChanged(_controller.text),
        indicatorBuilder:
            (context, editingController, chunkController, notifier) {
              return Row(
                children: [
                  DefaultCodeLineNumber(
                    controller: editingController,
                    notifier: notifier,
                  ),
                  DefaultCodeChunkIndicator(
                    width: 16,
                    controller: chunkController,
                    notifier: notifier,
                  ),
                ],
              );
            },
        shortcutOverrideActions: {
          CodeShortcutSaveIntent: CallbackAction<CodeShortcutSaveIntent>(
            onInvoke: (intent) {
              widget.onSave();
              return null;
            },
          ),
        },
      ),
    );
  }
}
