import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../core/api/opencode_client.dart';
import '../../core/api/providers.dart';
import '../../core/models/server_connection.dart';
import '../../shared/widgets/app_toast.dart';

class ConnectionScreen extends ConsumerStatefulWidget {
  const ConnectionScreen({super.key});

  @override
  ConsumerState<ConnectionScreen> createState() => _ConnectionScreenState();
}

class _ConnectionScreenState extends ConsumerState<ConnectionScreen> {
  final _hostController = TextEditingController(text: '127.0.0.1');
  final _portController = TextEditingController(text: '4096');
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _useHttps = false;
  bool _connecting = false;

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      headers: const [AppBar(title: Text('opencode companion'))],
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Card(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(
                        LucideIcons.server,
                        color: Colors.white,
                        size: 28,
                      ),
                    ),
                  ),
                  const Gap(16),
                  const Text('Connect to server').h3.textCenter,
                  const Gap(4),
                  const Text(
                    'Point this app at a running opencode serve.',
                  ).muted.textCenter,
                  const Gap(24),
                  const Text('Host').semiBold.small,
                  const Gap(6),
                  TextField(
                    controller: _hostController,
                    placeholder: const Text('127.0.0.1'),
                  ),
                  const Gap(12),
                  const Text('Port').semiBold.small,
                  const Gap(6),
                  TextField(
                    controller: _portController,
                    placeholder: const Text('4096'),
                    keyboardType: TextInputType.number,
                  ),
                  const Gap(12),
                  const Text('Username (optional)').semiBold.small,
                  const Gap(6),
                  TextField(
                    controller: _usernameController,
                    placeholder: const Text('opencode'),
                  ),
                  const Gap(12),
                  const Text('Password (optional)').semiBold.small,
                  const Gap(6),
                  TextField(
                    controller: _passwordController,
                    placeholder: const Text('OPENCODE_SERVER_PASSWORD'),
                    obscureText: true,
                  ),
                  const Gap(16),
                  Row(
                    children: [
                      Checkbox(
                        state: _useHttps
                            ? CheckboxState.checked
                            : CheckboxState.unchecked,
                        onChanged: (v) => setState(
                          () => _useHttps = v == CheckboxState.checked,
                        ),
                      ),
                      const Gap(8),
                      const Text('Use HTTPS'),
                    ],
                  ),
                  const Gap(24),
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
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
