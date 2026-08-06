import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../core/api/opencode_client.dart';
import '../../core/api/providers.dart';
import '../../core/models/server_config.dart';
import '../../core/models/server_connection.dart';
import '../../shared/widgets/app_toast.dart';

class ConnectionScreen extends ConsumerStatefulWidget {
  const ConnectionScreen({super.key, this.serverId});

  final String? serverId;

  @override
  ConsumerState<ConnectionScreen> createState() => _ConnectionScreenState();
}

class _ConnectionScreenState extends ConsumerState<ConnectionScreen>
    with SingleTickerProviderStateMixin {
  final _nameController = TextEditingController();
  final _hostController = TextEditingController(text: '127.0.0.1');
  final _portController = TextEditingController(text: '4096');
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _useHttps = false;
  bool _connecting = false;

  late final _logoController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 400),
  );
  late final _logoAnimation = CurvedAnimation(
    parent: _logoController,
    curve: Curves.easeOut,
  );

  bool get _isEditing => widget.serverId != null;

  @override
  void initState() {
    super.initState();
    _logoController.forward();
    if (_isEditing) {
      final state = ref.read(serverManagerProvider);
      final config =
          state.configs.where((c) => c.id == widget.serverId).firstOrNull;
      if (config != null) {
        _nameController.text = config.name;
        _hostController.text = config.connection.host;
        _portController.text = config.connection.port.toString();
        _usernameController.text = config.connection.username ?? '';
        _useHttps = config.connection.useHttps;
        _passwordController.text = state.password ?? '';
      }
    }
  }

  @override
  void dispose() {
    _logoController.dispose();
    _nameController.dispose();
    _hostController.dispose();
    _portController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  ServerConfig _buildConfig() {
    final connection = ServerConnection(
      host: _hostController.text.trim(),
      port: int.tryParse(_portController.text.trim()) ?? 4096,
      username: _usernameController.text.trim().isEmpty
          ? null
          : _usernameController.text.trim(),
      useHttps: _useHttps,
    );
    return ServerConfig(
      id: widget.serverId,
      name: _nameController.text.trim().isEmpty
          ? connection.baseUrl
          : _nameController.text.trim(),
      connection: connection,
    );
  }

  Future<void> _save() async {
    final host = _hostController.text.trim();
    final port = int.tryParse(_portController.text.trim());
    if (host.isEmpty || port == null) {
      showAppToast(context, title: 'Invalid host or port');
      return;
    }
    final config = _buildConfig();
    final password =
        _passwordController.text.isEmpty ? null : _passwordController.text;

    setState(() => _connecting = true);
    final client = OpencodeClient(
      connection: config.connection,
      password: password,
    );
    try {
      final healthy = await client.health();
      if (!mounted) return;
      if (!healthy) {
        showAppToast(context, title: 'Server responded but is not healthy');
        return;
      }
      final manager = ref.read(serverManagerProvider.notifier);
      if (_isEditing) {
        await manager.updateServer(config, password);
      } else {
        await manager.connect(config, password);
      }
      if (!mounted) return;
      showAppToast(
        context,
        title: _isEditing ? 'Server updated' : 'Connected',
        description: config.connection.baseUrl,
      );
      if (mounted && !_isEditing) {
        Navigator.of(context).pop();
      }
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
      headers: [
        AppBar(
          leading: [
            IconButton.ghost(
              icon: const Icon(LucideIcons.arrowLeft),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
          title: Text(_isEditing ? 'Edit server' : 'Add server'),
        ),
      ],
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: FadeTransition(
                    opacity: _logoAnimation,
                    child: ScaleTransition(
                      scale: _logoAnimation,
                      child: SvgPicture.asset(
                        'assets/logo/icon.svg',
                        width: 64,
                        height: 64,
                      ),
                    ),
                  ),
                ),
                const Gap(16),
                Center(
                  child: Text(
                    _isEditing ? 'Edit server' : 'Connect to server',
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                ),
                const Gap(4),
                Center(
                  child: Text(
                    'Point this app at a running SparkCode server.',
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.mutedForeground),
                  ),
                ),
                const Gap(24),
                const Text('Server name').semiBold.small,
                const Gap(6),
                TextField(
                  controller: _nameController,
                  placeholder: const Text('My Server'),
                  border: Border.all(color: Colors.transparent),
                ),
                const Gap(12),
                const Text('Host').semiBold.small,
                const Gap(6),
                TextField(
                  controller: _hostController,
                  placeholder: const Text('127.0.0.1'),
                  border: Border.all(color: Colors.transparent),
                ),
                const Gap(12),
                const Text('Port').semiBold.small,
                const Gap(6),
                TextField(
                  controller: _portController,
                  placeholder: const Text('4096'),
                  keyboardType: TextInputType.number,
                  border: Border.all(color: Colors.transparent),
                ),
                const Gap(12),
                const Text('Username (optional)').semiBold.small,
                const Gap(6),
                TextField(
                  controller: _usernameController,
                  placeholder: const Text('opencode'),
                  border: Border.all(color: Colors.transparent),
                ),
                const Gap(12),
                const Text('Password (optional)').semiBold.small,
                const Gap(6),
                TextField(
                  controller: _passwordController,
                  placeholder: const Text('OPENCODE_SERVER_PASSWORD'),
                  obscureText: true,
                  border: Border.all(color: Colors.transparent),
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
                  onPressed: _connecting ? null : _save,
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
                      : Text(_isEditing ? 'Save' : 'Connect'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
