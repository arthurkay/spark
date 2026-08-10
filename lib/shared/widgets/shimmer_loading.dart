import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../app/motion.dart';

/// Sweeps a highlight across [child] to indicate loading.
///
/// Colours come from the theme rather than being hardcoded — the previous fixed
/// light-grey palette was glaring in dark mode.
class ShimmerLoading extends StatefulWidget {
  const ShimmerLoading({
    super.key,
    required this.child,
    this.isLoading = true,
  });

  final Widget child;
  final bool isLoading;

  @override
  State<ShimmerLoading> createState() => _ShimmerLoadingState();
}

class _ShimmerLoadingState extends State<ShimmerLoading>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: Motion.shimmer);
    if (widget.isLoading) _controller.repeat();
  }

  @override
  void didUpdateWidget(ShimmerLoading oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Don't keep a ticker (and a per-frame ShaderMask) running once loaded.
    if (widget.isLoading && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.isLoading && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isLoading) return widget.child;

    final scheme = Theme.of(context).colorScheme;
    final base = scheme.muted;
    final highlight = scheme.mutedForeground.withValues(alpha: 0.18);
    final colors = [base, highlight, base];
    const stops = [0.0, 0.5, 1.0];

    // ShaderMask allocates an offscreen layer, so keep it isolated from the
    // rest of the tree — otherwise the sweep repaints its neighbours too.
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return ShaderMask(
            blendMode: BlendMode.srcATop,
            shaderCallback: (bounds) {
              final dx = _controller.value * 2 - 1;
              return LinearGradient(
                begin: Alignment(-1.0 + dx, 0),
                end: Alignment(1.0 + dx, 0),
                colors: colors,
                stops: stops,
              ).createShader(bounds);
            },
            child: child,
          );
        },
        child: widget.child,
      ),
    );
  }
}

/// A placeholder block sized like the content it stands in for.
class SkeletonBox extends StatelessWidget {
  const SkeletonBox({
    super.key,
    this.width,
    this.height = 16,
    this.borderRadius = 4,
  });

  final double? width;
  final double height;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.muted,
        borderRadius: BorderRadius.circular(borderRadius),
      ),
    );
  }
}
