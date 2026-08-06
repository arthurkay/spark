# Welcome Screen + Connection Screen Polish Plan

## Overview
Two changes: (1) a first-run welcome screen shown when no servers are configured,
(2) animated SVG logo on the connection screen replacing the static colored box.

---

## 1. First-Run Welcome Screen

### New file: `lib/features/connection/welcome_screen.dart`

A dedicated onboarding screen shown **only on first launch** (no servers configured).
Once a server is connected, this screen is never shown again.

#### Layout
```
[Top spacer — ~15%]
[App logo SVG, size 96, with fade+scale-in animation]
Gap(24)
"Spark"  — h1, bold
Gap(8)
"Your AI coding companion"  — muted subtitle
[Spacer]
[PrimaryButton: "Get started"]  → pushes ConnectionScreen
[Bottom safe area padding]
```

#### Animation
- Logo: fade in + scale from 0.8 → 1.0, 600ms ease-out
- Text: fade in with 200ms delay
- Button: fade in with 400ms delay
- Use `AnimationController` + `AnimatedBuilder` (no extra dependencies)

#### Widget structure
```dart
class WelcomeScreen extends ConsumerStatefulWidget { ... }

class _WelcomeScreenState extends State<WelcomeScreen>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 600),
  );
  // ... fade + scale animations
}
```

### Routing change: `lib/app/router.dart`

The `/` route currently always shows `ProjectsScreen`. Change it to conditionally
show `WelcomeScreen` when no servers exist.

```dart
GoRoute(
  path: '/',
  pageBuilder: (context, state) => CustomTransitionPage(
    key: state.pageKey,
    child: const _HomeRouter(),  // new wrapper widget
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      return FadeTransition(opacity: animation, child: child);
    },
  ),
),
```

`_HomeRouter` is a `ConsumerWidget` that watches `serverManagerProvider`:
```dart
class _HomeRouter extends ConsumerWidget {
  const _HomeRouter();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final configs = ref.watch(serverManagerProvider).configs;
    if (configs.isEmpty) return const WelcomeScreen();
    return const ProjectsScreen();
  }
}
```

After successful connection in `WelcomeScreen`, call `context.go('/')` which
now routes to `ProjectsScreen` (since configs are no longer empty).

### Estimated lines: ~80 (welcome_screen.dart) + ~15 (router.dart changes)

---

## 2. Connection Screen Animated Logo

### File: `lib/features/connection/connection_screen.dart`

Replace the static `Container` with icon (lines 149-163) with the SVG logo
and a fade-scale animation.

**Current:**
```dart
Container(
  width: 56, height: 56,
  decoration: BoxDecoration(
    color: Theme.of(context).colorScheme.primary,
    borderRadius: BorderRadius.circular(16),
  ),
  child: Icon(LucideIcons.server, size: 28, ...),
)
```

**New:**
```dart
FadeScaleTransition(
  animation: _logoAnimation,
  child: SvgPicture.asset(
    'assets/logo/icon.svg',
    width: 64,
    height: 64,
  ),
)
```

### Changes to `_ConnectionScreenState`:
- Add `SingleTickerProviderStateMixin`
- Create `AnimationController` + `CurvedAnimation` (400ms ease-out)
- Start animation in `initState()`
- Dispose controller in `dispose()`
- Replace the `Container` with `FadeScaleTransition` + `SvgPicture.asset`

### Estimated lines: ~20 (modifications to existing code)

---

## Files Summary

| File | Action | Lines (est.) |
|------|--------|-------------|
| `lib/features/connection/welcome_screen.dart` | **New** — first-run welcome | ~80 |
| `lib/app/router.dart` | Edit — add `_HomeRouter` wrapper | ~15 |
| `lib/features/connection/connection_screen.dart` | Edit — animated SVG logo | ~20 |

**Total: ~115 lines**

---

## Testing Checklist

- [ ] First launch (no servers): Welcome screen shown with animated logo
- [ ] Tap "Get started" → navigates to ConnectionScreen
- [ ] Connect successfully → navigates to ProjectsScreen
- [ ] Second launch (servers saved): ProjectsScreen shown directly (no welcome)
- [ ] Connection screen: SVG logo fades in on mount
- [ ] Connection screen editing mode: Logo still appears
- [ ] Back from ConnectionScreen returns to correct screen
- [ ] Animations smooth (no jank)
