class Endpoints {
  const Endpoints._();

  static const health = '/global/health';
  static const event = '/event';
  static const session = '/session';
  static const sessionStatus = '/session/status';
  static const config = '/config';
  static const configProviders = '/config/providers';
  static const agent = '/agent';
  static const file = '/file';
  static const fileContent = '/file/content';
  static const project = '/project';
  static const projectCurrent = '/project/current';
  static const vcs = '/vcs';

  static String sessionById(String id) => '/session/$id';
  static String messages(String id) => '/session/$id/message';
  static String promptAsync(String id) => '/session/$id/prompt_async';
  static String abort(String id) => '/session/$id/abort';
  static String diff(String id) => '/session/$id/diff';
  static String sessionCompact(String id) => '/session/$id/compact';
  static String permissionReply(String sessionId, String permissionId) =>
      '/session/$sessionId/permissions/$permissionId';
  static const questionList = '/question';
  static String questionReply(String requestId) => '/question/$requestId/reply';
  static String questionReject(String requestId) =>
      '/question/$requestId/reject';

  static String projectById(String id) => '/project/$id';

  static const pty = '/pty';
  static String ptyById(String id) => '/pty/$id';
  static String ptyConnect(String id) => '/pty/$id/connect';
  static String ptyConnectToken(String id) => '/pty/$id/connect-token';
}
