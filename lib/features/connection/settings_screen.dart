import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../core/api/opencode_client.dart';
import '../../core/api/providers.dart';
import '../../core/models/server_connection.dart';
import '../../core/storage/settings_provider.dart';
import '../../shared/widgets/app_toast.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _hostController = TextEditingController(text: '127.0.0.1');
  final _portController = TextEditingController(text: '4096');
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _useHttps = false;
  bool _connecting = false;

  static const _themeOptions = [
    ('system', 'System (adaptive)'),
    ('light', 'Light'),
    ('dark', 'Dark'),
  ];

  @override
  void initState() {
    super.initState();
    final state = ref.read(connectionControllerProvider);
    final conn = state.connection;
    if (conn != null) {
      _hostController.text = conn.host;
      _portController.text = conn.port.toString();
      _usernameController.text = conn.username ?? '';
      _useHttps = conn.useHttps;
      _passwordController.text = state.password ?? '';
    }
  }

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    final host = _hostController.text.trim();
    final port = int.tryParse(_portController.text.trim());
    if (host.isEmpty || port == null) {
      showAppToast(context, title: 'Invalid host or port');
      return;
    }
    final connection = ServerConnection(
      host: host,
      port: port,
      username: _usernameController.text.trim().isEmpty
          ? null
          : _usernameController.text.trim(),
      useHttps: _useHttps,
    );
    final password = _passwordController.text.isEmpty
        ? null
        : _passwordController.text;

    setState(() => _connecting = true);
    final client = OpencodeClient(connection: connection, password: password);
    try {
      final healthy = await client.health();
      if (!mounted) return;
      if (!healthy) {
        showAppToast(context, title: 'Server responded but is not healthy');
        return;
      }
      await ref
          .read(connectionControllerProvider.notifier)
          .connect(connection, password);
      if (!mounted) return;
      showAppToast(
        context,
        title: 'Connected',
        description: connection.baseUrl,
      );
    } on OpencodeApiException catch (e) {
      if (!mounted) return;
      showAppToast(context, title: 'Connection failed', description: e.message);
    } catch (e) {
      if (!mounted) return;
      showAppToast(context, title: 'Connection failed', description: '$e');
    } finally {
      client.close();
      if (mounted) setState(() => _connecting = false);
    }
  }

  String _labelFor(String value) {
    return _themeOptions
        .firstWhere((o) => o.$1 == value, orElse: () => _themeOptions.first)
        .$2;
  }

  @override
  Widget build(BuildContext context) {
    final connection = ref.watch(connectionControllerProvider).connection;
    final themeMode = ref.watch(themeModeProvider);
    return Scaffold(
      headers: [
        AppBar(
          leading: [
            IconButton.ghost(
              icon: const Icon(LucideIcons.arrowLeft),
              onPressed: () => context.pop(),
            ),
          ],
          title: const Text('Settings'),
        ),
      ],
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text('Server').small.semiBold.muted,
          const Gap(10),
          if (connection != null) ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.muted,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(LucideIcons.server, size: 18),
                  const Gap(10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(connection.baseUrl).medium,
                        const Gap(2),
                        const Text('Connected').small.muted,
                      ],
                    ),
                  ),
                  DestructiveButton(
                    density: ButtonDensity.compact,
                    onPressed: () async {
                      await ref
                          .read(connectionControllerProvider.notifier)
                          .disconnect();
                      if (context.mounted) setState(() {});
                    },
                    child: const Text('Disconnect'),
                  ),
                ],
              ),
            ),
            const Gap(16),
          ],
          const Gap(10),
          Text('Host').small.semiBold.muted,
          const Gap(6),
          TextField(
            controller: _hostController,
            placeholder: const Text('127.0.0.1'),
          ),
          const Gap(12),
          Text('Port').small.semiBold.muted,
          const Gap(6),
          TextField(
            controller: _portController,
            placeholder: const Text('4096'),
            keyboardType: TextInputType.number,
          ),
          const Gap(12),
          Text('Username (optional)').small.semiBold.muted,
          const Gap(6),
          TextField(
            controller: _usernameController,
            placeholder: const Text('opencode'),
          ),
          const Gap(12),
          Text('Password (optional)').small.semiBold.muted,
          const Gap(6),
          TextField(
            controller: _passwordController,
            placeholder: const Text('OPENCODE_SERVER_PASSWORD'),
            obscureText: true,
          ),
          const Gap(14),
          Row(
            children: [
              Checkbox(
                state: _useHttps
                    ? CheckboxState.checked
                    : CheckboxState.unchecked,
                onChanged: (v) =>
                    setState(() => _useHttps = v == CheckboxState.checked),
              ),
              const Gap(8),
              const Text('Use HTTPS'),
            ],
          ),
          const Gap(18),
          PrimaryButton(
            onPressed: _connecting ? null : _connect,
            child: _connecting
                ? const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(),
                      ),
                      Gap(8),
                      Text('Connecting...'),
                    ],
                  )
                : const Text('Connect'),
          ),
          const Gap(28),
          Text('Appearance').small.semiBold.muted,
          const Gap(10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.muted,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(LucideIcons.paintbrush, size: 18),
                const Gap(10),
                Expanded(child: const Text('Theme')),
                const Gap(8),
                Select<String>(
                  value: themeMode,
                  onChanged: (value) {
                    if (value != null) {
                      ref.read(themeModeProvider.notifier).setMode(value);
                    }
                  },
                  itemBuilder: (context, value) => Text(_labelFor(value)),
                  popup: (context) => SelectPopup(
                    items: SelectItemList(
                      children: [
                        for (final option in _themeOptions)
                          SelectItem(
                            value: option.$1,
                            builder: (context) => Text(option.$2).small,
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
