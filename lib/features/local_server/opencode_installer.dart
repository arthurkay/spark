import 'package:flutter/foundation.dart';

class InstallCommand {
  const InstallCommand({required this.executable, required this.args});

  final String executable;
  final List<String> args;
}

InstallCommand? installCommandFor(
  TargetPlatform platform, {
  required bool npmAvailable,
}) {
  if (platform == TargetPlatform.windows) {
    if (!npmAvailable) return null;
    return InstallCommand(
      executable: 'npm',
      args: ['install', '-g', 'opencode-ai'],
    );
  }
  return InstallCommand(
    executable: 'bash',
    args: ['-lc', 'curl -fsSL https://opencode.ai/install | bash'],
  );
}

InstallCommand upgradeCommandFor(String binary) {
  return InstallCommand(executable: binary, args: ['upgrade']);
}
