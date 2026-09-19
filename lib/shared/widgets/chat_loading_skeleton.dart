import 'package:shadcn_flutter/shadcn_flutter.dart';

import 'shimmer_loading.dart';

class ChatLoadingSkeleton extends StatelessWidget {
  const ChatLoadingSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return ShimmerLoading(
      isLoading: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _bubble(true, 0.65),
            const SizedBox(height: 24),
            _bubble(false, 0.45),
            const SizedBox(height: 24),
            _bubble(true, 0.8),
            const SizedBox(height: 24),
            _bubble(false, 0.55),
            const SizedBox(height: 24),
            _bubble(true, 0.35),
          ],
        ),
      ),
    );
  }

  static Widget _bubble(bool isUser, double widthFactor) {
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: Column(
          crossAxisAlignment: isUser
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            SkeletonBox(width: 200 * widthFactor, height: 14, borderRadius: 7),
            const SizedBox(height: 8),
            SkeletonBox(
              width: 200 * widthFactor * 0.7,
              height: 14,
              borderRadius: 7,
            ),
            if (!isUser) ...[
              const SizedBox(height: 8),
              SkeletonBox(
                width: 200 * widthFactor * 0.4,
                height: 14,
                borderRadius: 7,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
