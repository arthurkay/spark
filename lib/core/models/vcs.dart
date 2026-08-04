class VcsInfo {
  const VcsInfo({required this.branch});

  final String branch;

  factory VcsInfo.fromJson(Map<String, dynamic> json) {
    return VcsInfo(
      branch: (json['branch'] ?? '').toString(),
    );
  }
}
