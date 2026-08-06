const filePermissionTypes = {'glob', 'read', 'edit', 'write'};

bool isCommandEntry(String key, dynamic value) {
  if (value is! String || value.isEmpty) return false;
  final lowerKey = key.toLowerCase();
  if (lowerKey.contains('command') || lowerKey == 'cmd') return true;
  const commands = {
    'bash',
    'sh',
    'git',
    'npm',
    'yarn',
    'pnpm',
    'deno',
    'bun',
    'cargo',
    'go',
    'python',
    'python3',
    'node',
    'npx',
    'docker',
    'kubectl',
    'make',
    'sudo',
  };
  final firstWord = value.trim().split(RegExp(r'\s+')).first;
  return commands.contains(firstWord);
}
