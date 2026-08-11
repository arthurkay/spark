import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 600),
  );
  late final _logoScale = Tween<double>(begin: 0.8, end: 1.0).animate(
    CurvedAnimation(parent: _controller, curve: Curves.easeOut),
  );
  late final _logoFade = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0, 0.6, curve: Curves.easeOut),
  );
  late final _textFade = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0.2, 0.8, curve: Curves.easeOut),
  );
  late final _buttonFade = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0.4, 1.0, curve: Curves.easeOut),
  );

  @override
  void initState() {
    super.initState();
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Spacer(flex: 3),
                FadeTransition(
                  opacity: _logoFade,
                  child: ScaleTransition(
                    scale: _logoScale,
                    child: SvgPicture.asset(
                      'assets/logo/icon.svg',
                      width: 96,
                      height: 96,
                    ),
                  ),
                ),
                const Gap(24),
                FadeTransition(
                  opacity: _textFade,
                  child: const Text(
                    'Spark',
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const Gap(8),
                FadeTransition(
                  opacity: _textFade,
                  child: Text(
                    'Your AI coding companion',
                    style: TextStyle(
                      fontSize: 16,
                      color: Theme.of(context).colorScheme.mutedForeground,
                    ),
                  ),
                ),
                const Spacer(flex: 4),
                FadeTransition(
                  opacity: _buttonFade,
                  child: PrimaryButton(
                    onPressed: () {
                      context.push('/servers/add');
                    },
                    child: const Text('Get started'),
                  ),
                ),
                const Spacer(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
