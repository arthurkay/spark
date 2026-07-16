import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../core/models/permission.dart';

typedef PermissionResponder = void Function(String response, bool remember);

void showPermissionSheet({
  required BuildContext context,
  required PermissionRequest permission,
  required PermissionResponder onRespond,
}) {
  openSheetOverlay(
    context: context,
    position: OverlayPosition.bottom,
    barrierDismissible: false,
    builder: (context) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(LucideIcons.shieldQuestion),
                  const Gap(8),
                  const Text('Permission request').h4,
                ],
              ),
              const Gap(12),
              Text(permission.title ?? permission.type ?? 'Allow this action?'),
              if (permission.metadata.isNotEmpty) ...[
                const Gap(12),
                Card(
                  padding: const EdgeInsets.all(12),
                  child: SelectableText(
                    permission.metadata.entries
                        .map((e) => '${e.key}: ${e.value}')
                        .join('\n'),
                  ).mono.small,
                ),
              ],
              const Gap(20),
              PrimaryButton(
                onPressed: () {
                  onRespond('always', true);
                  closeSheet(context);
                },
                child: const Text('Always allow'),
              ),
              const Gap(8),
              OutlineButton(
                onPressed: () {
                  onRespond('once', false);
                  closeSheet(context);
                },
                child: const Text('Allow once'),
              ),
              const Gap(8),
              DestructiveButton(
                onPressed: () {
                  onRespond('reject', false);
                  closeSheet(context);
                },
                child: const Text('Reject'),
              ),
            ],
          ),
        ),
      );
    },
  );
}
