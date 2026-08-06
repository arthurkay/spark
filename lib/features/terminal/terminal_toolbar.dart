import 'package:flutter/services.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:xterm/xterm.dart';

class TerminalToolbar extends StatefulWidget {
  const TerminalToolbar({super.key, required this.terminal});

  final Terminal terminal;

  @override
  State<TerminalToolbar> createState() => _TerminalToolbarState();
}

class _TerminalToolbarState extends State<TerminalToolbar> {
  bool _ctrlActive = false;

  void _sendKey(TerminalKey key) {
    widget.terminal.keyInput(key, ctrl: _ctrlActive);
    if (_ctrlActive) setState(() => _ctrlActive = false);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.card,
        border: Border(
          top: BorderSide(
            color: Theme.of(context).colorScheme.border,
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildKey(
            icon: LucideIcons.arrowUp,
            onPressed: () => _sendKey(TerminalKey.arrowUp),
          ),
          _buildKey(
            icon: LucideIcons.arrowDown,
            onPressed: () => _sendKey(TerminalKey.arrowDown),
          ),
          _buildKey(
            icon: LucideIcons.arrowLeft,
            onPressed: () => _sendKey(TerminalKey.arrowLeft),
          ),
          _buildKey(
            icon: LucideIcons.arrowRight,
            onPressed: () => _sendKey(TerminalKey.arrowRight),
          ),
          _buildTextKey(
            label: 'Tab',
            onPressed: () => _sendKey(TerminalKey.tab),
          ),
          _buildToggleKey(
            label: 'Ctrl',
            active: _ctrlActive,
            onPressed: () => setState(() => _ctrlActive = !_ctrlActive),
          ),
          _buildTextKey(
            label: 'Esc',
            onPressed: () => _sendKey(TerminalKey.escape),
          ),
        ],
      ),
    );
  }

  Widget _buildKey({
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    return IconButton.ghost(
      icon: Icon(icon, size: 18),
      onPressed: onPressed,
    );
  }

  Widget _buildTextKey({
    required String label,
    required VoidCallback onPressed,
  }) {
    return GhostButton(
      onPressed: onPressed,
      child: Text(label, style: const TextStyle(fontSize: 13)),
    );
  }

  Widget _buildToggleKey({
    required String label,
    required bool active,
    required VoidCallback onPressed,
  }) {
    return GhostButton(
      onPressed: onPressed,
      child: Text(
        label,
        style: TextStyle(
          fontSize: 13,
          fontWeight: active ? FontWeight.bold : FontWeight.normal,
          color: active ? Theme.of(context).colorScheme.primary : null,
        ),
      ),
    );
  }
}
