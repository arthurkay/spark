import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:xterm/xterm.dart' as xterm;

import '../chat/chat_provider.dart';
import 'terminal_provider.dart';
import 'terminal_toolbar.dart';

class TerminalSheet extends ConsumerStatefulWidget {
  const TerminalSheet({super.key, this.directory, this.sessionId});

  final String? directory;
  final String? sessionId;

  @override
  ConsumerState<TerminalSheet> createState() => _TerminalSheetState();
}

class _TerminalSheetState extends ConsumerState<TerminalSheet> {
  String? _resolvedDirectory;
  bool _killed = false;

  @override
  void initState() {
    super.initState();
    _resolveDirectory();
  }

  @override
  void dispose() {
    if (!_killed) {
      _killed = true;
      final ctrl = _resolvedDirectory != null
          ? ref.read(terminalProvider(_resolvedDirectory))
          : null;
      ctrl?.kill();
    }
    super.dispose();
  }

  Future<void> _resolveDirectory() async {
    if (widget.directory != null) {
      setState(() => _resolvedDirectory = widget.directory);
      return;
    }
    if (widget.sessionId != null) {
      final dir = await ref.read(
        sessionDirectoryProvider(widget.sessionId!).future,
      );
      if (mounted) setState(() => _resolvedDirectory = dir);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = _resolvedDirectory != null
        ? ref.watch(terminalProvider(_resolvedDirectory))
        : null;
    final state = ctrl?.state;

    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(top: 12, bottom: bottomInset),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Text(state?.session?.title ?? 'Terminal').h4,
                  const Spacer(),
                  IconButton.ghost(
                    icon: const Icon(LucideIcons.x, size: 16),
                    onPressed: () {
                      ctrl?.kill();
                      closeSheet(context);
                    },
                  ),
                ],
              ),
            ),
            const Gap(8),
            Flexible(
              child: SizedBox(
                height: MediaQuery.of(context).size.height * 0.6,
                child: _buildBody(ctrl, state),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(PtyController? ctrl, PtyConnectionState? state) {
    if (ctrl == null || state == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state.connecting) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            Gap(16),
            Text('Creating terminal...'),
          ],
        ),
      );
    }

    if (state.error != null && !state.connected) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(LucideIcons.circleAlert, size: 32),
            const Gap(12),
            Text(state.error!, textAlign: TextAlign.center),
            const Gap(12),
            PrimaryButton(
              onPressed: () => ctrl.init(),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        Expanded(
          child: xterm.TerminalView(
            ctrl.terminal,
            autofocus: true,
            hardwareKeyboardOnly: false,
            textStyle: const xterm.TerminalStyle(
              fontFamily: 'monospace',
              fontSize: 14,
            ),
          ),
        ),
        TerminalToolbar(terminal: ctrl.terminal),
      ],
    );
  }
}

void openTerminalSheet(
  BuildContext context, {
  String? directory,
  String? sessionId,
}) {
  openSheetOverlay(
    context: context,
    position: OverlayPosition.bottom,
    barrierDismissible: true,
    builder: (sheetContext) => TerminalSheet(
      directory: directory,
      sessionId: sessionId,
    ),
  );
}
