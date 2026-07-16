import 'session.dart';

class Project {
  const Project({
    required this.id,
    required this.worktree,
    this.vcs,
    this.time,
  });

  final String id;
  final String worktree;
  final String? vcs;
  final SessionTime? time;

  factory Project.fromJson(Map<String, dynamic> json) {
    final timeJson = json['time'];
    return Project(
      id: (json['id'] ?? '').toString(),
      worktree: (json['worktree'] ?? '').toString(),
      vcs: json['vcs'] as String?,
      time: timeJson is Map<String, dynamic>
          ? SessionTime.fromJson(timeJson)
          : null,
    );
  }

  bool get isGlobal => id == 'global';
}
