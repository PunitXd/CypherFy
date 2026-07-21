import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_strings.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/router/app_router.dart';
import '../../services/active_room_store.dart';
import '../providers/auth_provider.dart';

/// Splash — animates the lock in, restores any session, then routes home.
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..forward();
    // Defer until after the first frame — modifying a provider (restore() sets
    // loading state) during initState/build throws in Riverpod.
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  Future<void> _bootstrap() async {
    // We're past the cold-load gate now — allow normal in-app navigation so the
    // routes we push below aren't bounced back to Splash by the redirect.
    routerBooted = true;
    // Wait for session restore (driven — and de-duplicated — by the app root)
    // so we land already knowing whether the user is signed in.
    // Guarded so a network/storage failure can never strand us on splash.
    try {
      await ref.read(authProvider.notifier).restore();
    } catch (e) {
      // Non-fatal — continue to home as a guest.
      debugPrint('Splash bootstrap error: $e');
    }
    // If the user was in a room when the tab was refreshed, drop them back into
    // it (the room key is re-derived from the code/roomId, the alias is kept).
    final room = await ActiveRoomStore.instance.read();
    await Future.delayed(const Duration(milliseconds: 900));
    if (!mounted) return;
    // Go straight to the room (replacing the stack) rather than mounting Home
    // underneath it: Home grabs and reconnects the socket on mount, which would
    // race with — and clobber — the chat's own socket join, leaving the room
    // without its roster/messages. The chat's AppBar has its own back button
    // that returns Home when there's nothing to pop.
    if (room != null) {
      context.go(Routes.chat, extra: room);
    } else {
      context.go(Routes.home);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Stack(
        children: [
          Center(
            child: FadeTransition(
              opacity: _controller,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ScaleTransition(
                    scale: CurvedAnimation(
                      parent: _controller,
                      curve: Curves.easeOutBack,
                    ),
                    // Logo tile — rounded surface box with the lock mark.
                    child: Container(
                      width: 88,
                      height: 88,
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: AppColors.surfaceContainerHigh, width: 0.5),
                      ),
                      child: Icon(Icons.lock_outline,
                          size: 44, color: AppColors.primary),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(AppStrings.appName, style: AppTextStyles.display),
                  const SizedBox(height: 8),
                  Text(
                    AppStrings.tagline.toUpperCase(),
                    style: AppTextStyles.monoLabel.copyWith(letterSpacing: 2),
                  ),
                ],
              ),
            ),
          ),
          // Bottom security anchor.
          Positioned(
            left: 0,
            right: 0,
            bottom: 40,
            child: FadeTransition(
              opacity: _controller,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.shield,
                      size: 16,
                      color: AppColors.primary.withValues(alpha: 0.6)),
                  const SizedBox(width: 8),
                  Text(
                    'E2E ENCRYPTED',
                    style: AppTextStyles.monoLabel.copyWith(
                      letterSpacing: 2,
                      color: AppColors.primary.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
