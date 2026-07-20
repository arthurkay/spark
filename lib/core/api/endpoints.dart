class Endpoints {
  const Endpoints._();

  static const health = '/global/health';
  static const event = '/event';
  static const session = '/session';
  static const sessionStatus = '/session/status';
  static const configProviders = '/config/providers';
  static const agent = '/agent';
  static const file = '/file';
  static const fileContent = '/file/content';
  static const project = '/project';
  static const projectCurrent = '/project/current';
  static const permissionList = '/permission';

  static String sessionById(String id) => '/session/$id';
  static String messages(String id) => '/session/$id/message';
  static String promptAsync(String id) => '/session/$id/prompt_async';
  static String prompt(String id) => '/session/$id/message';
  static String abort(String id) => '/session/$id/abort';
  static String diff(String id) => '/session/$id/diff';
  static String permissionReply(String requestId) =>
      '/permission/$requestId/reply';
  static const questionList = '/question';
  static String questionReply(String requestId) => '/question/$requestId/reply';
  static String questionReject(String requestId) =>
      '/question/$requestId/reject';
}
