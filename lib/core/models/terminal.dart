class PtySession {
  const PtySession({
    required this.id,
    required this.title,
    required this.command,
    this.args = const [],
    required this.cwd,
    required this.status,
    this.pid,
    this.exitCode,
  });

  final String id;
  final String title;
  final String command;
  final List<String> args;
  final String cwd;
  final String status;
  final int? pid;
  final int? exitCode;

  bool get isRunning => status == 'running';

  factory PtySession.fromJson(Map<String, dynamic> json) {
    return PtySession(
      id: (json['id'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      command: (json['command'] ?? '').toString(),
      args:
          (json['args'] as List<dynamic>?)?.map((e) => e.toString()).toList() ??
              const [],
      cwd: (json['cwd'] ?? '').toString(),
      status: (json['status'] ?? '').toString(),
      pid: json['pid'] != null ? int.tryParse(json['pid'].toString()) : null,
      exitCode: json['exitCode'] != null
          ? int.tryParse(json['exitCode'].toString())
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'command': command,
        'args': args,
        'cwd': cwd,
        'status': status,
        if (pid != null) 'pid': pid,
        if (exitCode != null) 'exitCode': exitCode,
      };
}
