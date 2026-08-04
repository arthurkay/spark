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
  static String prompt(String id) => '/session/$id/message';
  static String abort(String id) => '/session/$id/abort';
  static String diff(String id) => '/session/$id/diff';
  static String sessionCompact(String id) => '/session/$id/compact';
  static String permissionReply(String sessionId, String permissionId) =>
      '/session/$sessionId/permissions/$permissionId';
  static const questionList = '/question';
  static String questionReply(String requestId) => '/question/$requestId/reply';
  static String questionReject(String requestId) =>
      '/question/$requestId/reject';

  static const projectGitInit = '/project/git/init';
  static String projectById(String id) => '/project/$id';
  static String projectDirectories(String id) => '/project/$id/directories';

  static const workspaces = '/experimental/workspace';
  static const workspaceSync = '/experimental/workspace/sync-list';

  static const worktrees = '/experimental/worktree';

  static String projectCopy(String id) => '/experimental/project/$id/copy';
  static String projectCopyGenerateName(String id) =>
      '/experimental/project/$id/copy/generate-name';
  static String projectCopyRefresh(String id) =>
      '/experimental/project/$id/copy/refresh';
}
