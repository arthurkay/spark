import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:xterm/xterm.dart' as xterm;

import '../chat/chat_provider.dart';
import 'terminal_provider.dart';
import 'terminal_toolbar.dart';

class TerminalScreen extends ConsumerStatefulWidget {
  const TerminalScreen({super.key, this.directory, this.sessionId});

  final String? directory;
  final String? sessionId;

  @override
  ConsumerState<TerminalScreen> createState() => _TerminalScreenState();
}

class _TerminalScreenState extends ConsumerState<TerminalScreen> {
  String? _resolvedDirectory;

  @override
  void initState() {
    super.initState();
    _resolveDirectory();
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

    return Scaffold(
      resizeToAvoidBottomInset: true,
      headers: [
        AppBar(
          leading: [
            // Back keeps the shell alive; the provider is keep-alive, so
            // returning here (or opening the sheet) reattaches with scrollback.
            IconButton.ghost(
              icon: const Icon(LucideIcons.arrowLeft),
              onPressed: () => context.pop(),
            ),
          ],
          title: Text(state?.session?.title ?? 'Terminal'),
          trailing: [
            if (state?.connected == true)
              // Ends the shell session for real.
              IconButton.ghost(
                icon: Icon(
                  LucideIcons.trash2,
                  color: Theme.of(context).colorScheme.destructive,
                ),
                onPressed: () async {
                  await ctrl?.kill();
                  ref.invalidate(terminalProvider(_resolvedDirectory));
                  if (context.mounted) context.pop();
                },
              ),
          ],
        ),
      ],
      child: _buildBody(ctrl, state),
    );
  }

  Widget _buildBody(PtyController? ctrl, PtyConnectionState? state) {
    if (ctrl == null || state == null) {
      return const Center(
        child: CircularProgressIndicator(),
      );
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
            const Icon(LucideIcons.circleAlert, size: 48),
            const Gap(16),
            Text(state.error!),
            const Gap(16),
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
