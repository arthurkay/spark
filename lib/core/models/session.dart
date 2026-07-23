class SessionTime {
  const SessionTime({this.created, this.updated});

  final int? created;
  final int? updated;

  factory SessionTime.fromJson(Map<String, dynamic> json) {
    return SessionTime(
      created: (json['created'] as num?)?.toInt(),
      updated: (json['updated'] as num?)?.toInt(),
    );
  }

  Map<String, dynamic> toJson() => {
        if (created != null) 'created': created,
        if (updated != null) 'updated': updated,
      };
}

class Session {
  const Session({
    required this.id,
    this.title,
    this.parentID,
    this.directory,
    this.time,
  });

  final String id;
  final String? title;
  final String? parentID;
  final String? directory;
  final SessionTime? time;

  factory Session.fromJson(Map<String, dynamic> json) {
    final timeJson = json['time'];
    return Session(
      id: (json['id'] ?? '').toString(),
      title: json['title'] as String?,
      parentID: json['parentID'] as String?,
      directory: json['directory'] as String?,
      time: timeJson is Map<String, dynamic>
          ? SessionTime.fromJson(timeJson)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        if (title != null) 'title': title,
        if (parentID != null) 'parentID': parentID,
        if (directory != null) 'directory': directory,
        if (time != null) 'time': time!.toJson(),
      };
}
