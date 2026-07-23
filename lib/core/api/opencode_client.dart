import 'dart:convert';

import 'package:dio/dio.dart';

import '../models/attachment.dart';
import '../models/file_node.dart';
import '../models/message.dart';
import '../models/project.dart';
import '../models/provider.dart';
import '../models/question.dart';
import '../models/server_connection.dart';
import '../models/session.dart';
import 'endpoints.dart';

class OpencodeApiException implements Exception {
  OpencodeApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => 'OpencodeApiException($statusCode): $message';
}

class OpencodeClient {
  OpencodeClient({required this.connection, this.password, Dio? dio})
      : _dio = dio ?? Dio() {
    _dio.options
      ..baseUrl = connection.baseUrl
      ..connectTimeout = const Duration(seconds: 15)
      ..receiveTimeout = const Duration(seconds: 60)
      ..sendTimeout = const Duration(seconds: 30)
      ..headers = _buildHeaders();
  }

  final ServerConnection connection;
  final String? password;
  final Dio _dio;

  Dio get dio => _dio;

  Map<String, dynamic> _buildHeaders() {
    final headers = <String, dynamic>{};
    if (password != null && password!.isNotEmpty) {
      final user = connection.username?.isNotEmpty == true
          ? connection.username!
          : 'opencode';
      final token = base64Encode(utf8.encode('$user:$password'));
      headers['Authorization'] = 'Basic $token';
    }
    return headers;
  }

  Never _rethrow(DioException e) {
    final status = e.response?.statusCode;
    final data = e.response?.data;
    String? message;
    if (data is Map) {
      final raw = data['message'];
      if (raw is String && raw.isNotEmpty) {
        message = raw;
      } else if (data['_tag'] is String) {
        message = data['_tag'] as String;
      }
    }
    message ??= switch (status) {
      400 => 'Bad request',
      401 => 'Unauthorized',
      403 => 'Forbidden',
      404 => 'Not found',
      409 => 'Conflict',
      500 => 'Server error',
      _ => 'Request failed',
    };
    throw OpencodeApiException(message, statusCode: status);
  }

  Future<bool> health() async {
    try {
      final res = await _dio.get<dynamic>(Endpoints.health);
      final data = res.data;
      if (data is Map) return data['healthy'] == true;
      return res.statusCode == 200;
    } on DioException catch (e) {
      _rethrow(e);
    }
  }

  Future<List<Session>> listSessions({String? directory}) async {
    try {
      final res = await _dio.get<List<dynamic>>(
        Endpoints.session,
        queryParameters: {if (directory != null) 'directory': directory},
      );
      return (res.data ?? [])
          .whereType<Map<String, dynamic>>()
          .map(Session.fromJson)
          .toList();
    } on DioException catch (e) {
      _rethrow(e);
    }
  }

  Future<Session> createSession({
    String? title,
    String? parentID,
    String? directory,
  }) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        Endpoints.session,
        queryParameters: {if (directory != null) 'directory': directory},
        data: {
          if (title != null) 'title': title,
          if (parentID != null) 'parentID': parentID,
        },
      );
      return Session.fromJson(res.data!);
    } on DioException catch (e) {
      _rethrow(e);
    }
  }

  Future<void> deleteSession(String id) async {
    try {
      await _dio.delete<dynamic>(Endpoints.sessionById(id));
    } on DioException catch (e) {
      _rethrow(e);
    }
  }

  Future<Session> renameSession(String id, String title) async {
    try {
      final res = await _dio.patch<Map<String, dynamic>>(
        Endpoints.sessionById(id),
        data: {'title': title},
      );
      return Session.fromJson(res.data!);
    } on DioException catch (e) {
      _rethrow(e);
    }
  }

  Future<Session> forkSession(String id, {String? messageID}) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        Endpoints.sessionFork(id),
        data: {if (messageID != null) 'messageID': messageID},
      );
      return Session.fromJson(res.data!);
    } on DioException catch (e) {
      _rethrow(e);
    }
  }

  Future<Session> shareSession(String id) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        Endpoints.sessionShare(id),
      );
      return Session.fromJson(res.data!);
    } on DioException catch (e) {
      _rethrow(e);
    }
  }

  Future<Session> unshareSession(String id) async {
    try {
      final res = await _dio.delete<Map<String, dynamic>>(
        Endpoints.sessionShare(id),
      );
      return Session.fromJson(res.data!);
    } on DioException catch (e) {
      _rethrow(e);
    }
  }

  Future<void> compactSession(String id) async {
    try {
      await _dio.post<dynamic>(Endpoints.sessionCompact(id));
    } on DioException catch (e) {
      _rethrow(e);
    }
  }

  Future<Map<String, dynamic>> sessionStatus() async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(Endpoints.sessionStatus);
      return res.data ?? {};
    } on DioException catch (e) {
      _rethrow(e);
    }
  }

  Future<List<MessageWithParts>> listMessages(
    String sessionId, {
    int? limit,
    String? before,
  }) async {
    try {
      final res = await _dio.get<List<dynamic>>(
        Endpoints.messages(sessionId),
        queryParameters: {
          if (limit != null) 'limit': limit,
          if (before != null) 'before': before,
        },
      );
      return (res.data ?? [])
          .whereType<Map<String, dynamic>>()
          .map(MessageWithParts.fromJson)
          .toList();
    } on DioException catch (e) {
      _rethrow(e);
    }
  }

  Future<void> sendPromptAsync({
    required String sessionId,
    required String text,
    ModelSelection? model,
    String? agent,
    List<Attachment> attachments = const [],
  }) async {
    try {
      final parts = <Map<String, dynamic>>[
        {'type': 'text', 'text': text},
      ];
      for (final a in attachments) {
        parts.add({
          'type': 'file',
          'mime': a.mime,
          'filename': a.name,
          'url': 'data:${a.mime};base64,${base64Encode(a.bytes)}',
        });
      }
      await _dio.post<dynamic>(
        Endpoints.promptAsync(sessionId),
        data: {
          if (model != null) 'model': model.toJson(),
          if (agent != null) 'agent': agent,
          'parts': parts,
        },
      );
    } on DioException catch (e) {
      _rethrow(e);
    }
  }

  Future<bool> abort(String sessionId) async {
    try {
      final res = await _dio.post<dynamic>(Endpoints.abort(sessionId));
      return res.data == true;
    } on DioException catch (e) {
      _rethrow(e);
    }
  }

  Future<void> respondPermission({
    required String sessionId,
    required String permissionId,
    required String reply,
  }) async {
    try {
      await _dio.post<dynamic>(
        Endpoints.permissionReply(sessionId, permissionId),
        data: {'response': reply},
      );
    } on DioException catch (e) {
      _rethrow(e);
    }
  }

  Future<Map<String, dynamic>> getConfig() async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(Endpoints.config);
      return res.data ?? {};
    } on DioException catch (e) {
      _rethrow(e);
    }
  }

  Future<List<ProviderInfo>> listProviders() async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        Endpoints.configProviders,
      );
      final providers = res.data?['providers'] as List<dynamic>? ?? [];
      return providers
          .whereType<Map<String, dynamic>>()
          .map(ProviderInfo.fromJson)
          .toList();
    } on DioException catch (e) {
      _rethrow(e);
    }
  }

  Future<Map<String, dynamic>> configProvidersRaw() async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        Endpoints.configProviders,
      );
      return res.data ?? {};
    } on DioException catch (e) {
      _rethrow(e);
    }
  }

  Future<List<Agent>> listAgents() async {
    try {
      final res = await _dio.get<List<dynamic>>(Endpoints.agent);
      return (res.data ?? [])
          .whereType<Map<String, dynamic>>()
          .map(Agent.fromJson)
          .toList();
    } on DioException catch (e) {
      _rethrow(e);
    }
  }

  Future<List<FileNode>> listFiles(String path, {String? directory}) async {
    try {
      final res = await _dio.get<List<dynamic>>(
        Endpoints.file,
        queryParameters: {
          'path': path,
          if (directory != null) 'directory': directory,
        },
      );
      return (res.data ?? [])
          .whereType<Map<String, dynamic>>()
          .map(FileNode.fromJson)
          .toList();
    } on DioException catch (e) {
      _rethrow(e);
    }
  }

  Future<FileContent> readFile(String path, {String? directory}) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        Endpoints.fileContent,
        queryParameters: {
          'path': path,
          if (directory != null) 'directory': directory,
        },
      );
      return FileContent.fromJson(res.data ?? {});
    } on DioException catch (e) {
      _rethrow(e);
    }
  }

  Future<List<Project>> listProjects() async {
    try {
      final res = await _dio.get<List<dynamic>>(Endpoints.project);
      return (res.data ?? [])
          .whereType<Map<String, dynamic>>()
          .map(Project.fromJson)
          .toList();
    } on DioException catch (e) {
      _rethrow(e);
    }
  }

  Future<Project?> currentProject() async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        Endpoints.projectCurrent,
      );
      final data = res.data;
      if (data == null) return null;
      return Project.fromJson(data);
    } on DioException catch (e) {
      _rethrow(e);
    }
  }

  Future<Project> initProjectGit({String? directory}) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        Endpoints.projectGitInit,
        queryParameters: {if (directory != null) 'directory': directory},
      );
      return Project.fromJson(res.data!);
    } on DioException catch (e) {
      _rethrow(e);
    }
  }

  Future<Project> updateProject(
    String id, {
    String? name,
    Map<String, dynamic>? icon,
    Map<String, dynamic>? commands,
  }) async {
    try {
      final body = <String, dynamic>{};
      if (name != null) body['name'] = name;
      if (icon != null) body['icon'] = icon;
      if (commands != null) body['commands'] = commands;
      final res = await _dio.patch<Map<String, dynamic>>(
        Endpoints.projectById(id),
        data: body,
      );
      return Project.fromJson(res.data!);
    } on DioException catch (e) {
      _rethrow(e);
    }
  }

  Future<List<String>> listProjectDirectories(String id) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        Endpoints.projectDirectories(id),
      );
      final dirs = res.data?['directories'];
      if (dirs is List) {
        return dirs.whereType<String>().toList();
      }
      return const [];
    } on DioException catch (e) {
      _rethrow(e);
    }
  }

  Future<Map<String, dynamic>> createWorktree(Map<String, dynamic> input,
      {String? directory}) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        Endpoints.worktrees,
        data: input,
        queryParameters: {if (directory != null) 'directory': directory},
      );
      return res.data ?? const <String, dynamic>{};
    } on DioException catch (e) {
      _rethrow(e);
    }
  }

  Future<List<String>> listWorktrees({String? directory}) async {
    try {
      final res = await _dio.get<List<dynamic>>(
        Endpoints.worktrees,
        queryParameters: {if (directory != null) 'directory': directory},
      );
      return (res.data ?? []).whereType<String>().toList();
    } on DioException catch (e) {
      _rethrow(e);
    }
  }

  Future<Map<String, dynamic>> createProjectCopy(
    String id, {
    required String directory,
    String? name,
    String? strategy,
    String? sourceDirectory,
  }) async {
    try {
      final body = <String, dynamic>{
        'directory': directory,
        if (name != null) 'name': name,
        if (strategy != null) 'strategy': strategy,
      };
      final res = await _dio.post<Map<String, dynamic>>(
        Endpoints.projectCopy(id),
        data: body,
        queryParameters: {
          if (sourceDirectory != null) 'directory': sourceDirectory
        },
      );
      return res.data ?? const <String, dynamic>{};
    } on DioException catch (e) {
      _rethrow(e);
    }
  }

  Future<String> generateProjectCopyName(
    String id, {
    String? directory,
  }) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        Endpoints.projectCopyGenerateName(id),
        queryParameters: {if (directory != null) 'directory': directory},
      );
      return (res.data?['name'] as String?) ?? '';
    } on DioException catch (e) {
      _rethrow(e);
    }
  }

  Future<void> refreshProjectCopy(String id, {String? directory}) async {
    try {
      await _dio.post<dynamic>(
        Endpoints.projectCopyRefresh(id),
        queryParameters: {if (directory != null) 'directory': directory},
      );
    } on DioException catch (e) {
      _rethrow(e);
    }
  }

  Future<Session?> getSession(String id) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        Endpoints.sessionById(id),
      );
      final data = res.data;
      if (data == null) return null;
      return Session.fromJson(data);
    } on DioException catch (e) {
      _rethrow(e);
    }
  }

  Future<List<FileDiff>> sessionDiff(
    String sessionId, {
    String? messageId,
  }) async {
    try {
      final res = await _dio.get<List<dynamic>>(
        Endpoints.diff(sessionId),
        queryParameters: {if (messageId != null) 'messageID': messageId},
      );
      return (res.data ?? [])
          .whereType<Map<String, dynamic>>()
          .map(FileDiff.fromJson)
          .toList();
    } on DioException catch (e) {
      _rethrow(e);
    }
  }

  Future<List<QuestionRequest>> listQuestions() async {
    try {
      final res = await _dio.get<List<dynamic>>(Endpoints.questionList);
      return (res.data ?? [])
          .whereType<Map<String, dynamic>>()
          .map(QuestionRequest.fromJson)
          .toList();
    } on DioException catch (e) {
      _rethrow(e);
    }
  }

  Future<void> replyQuestion({
    required String requestId,
    required List<List<String>> answers,
  }) async {
    try {
      await _dio.post<dynamic>(
        Endpoints.questionReply(requestId),
        data: {'answers': answers},
      );
    } on DioException catch (e) {
      _rethrow(e);
    }
  }

  Future<void> rejectQuestion({required String requestId}) async {
    try {
      await _dio.post<dynamic>(Endpoints.questionReject(requestId));
    } on DioException catch (e) {
      _rethrow(e);
    }
  }

  void close() => _dio.close(force: true);
}
