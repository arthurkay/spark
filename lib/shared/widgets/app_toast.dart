import 'package:shadcn_flutter/shadcn_flutter.dart';

void showAppToast(
  BuildContext context, {
  required String title,
  String? description,
}) {
  showToast(
    context: context,
    location: ToastLocation.bottomCenter,
    builder: (context, overlay) {
      return SurfaceCard(
        child: Basic(
          title: Text(title),
          subtitle: description != null ? Text(description) : null,
          trailing: IconButton.ghost(
            icon: const Icon(LucideIcons.x),
            onPressed: overlay.close,
          ),
        ),
      );
    },
  );
}
