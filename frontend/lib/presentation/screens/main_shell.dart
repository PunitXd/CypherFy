import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/router/app_router.dart';
import '../providers/auth_provider.dart';
import '../providers/pending_requests_provider.dart';

/// Bumped whenever we return to the tab shell from a pushed route (chat, room,
/// other-user profile). Home watches this to re-refresh its DM list and
/// re-establish the realtime socket the chat screen tore down on exit — the
/// shell's branch route never receives a route-observer callback for pushes on
/// the ROOT navigator, so the shell (which does) relays the signal here.
final homeRefreshTick = StateProvider<int>((_) => 0);

/// Tab shell hosting Home / Search / Profile. The bottom bar is only shown when
/// logged in — a guest sees the standalone (logged-out) Home with no tabs.
class MainShell extends ConsumerStatefulWidget {
  final StatefulNavigationShell navigationShell;
  const MainShell({super.key, required this.navigationShell});

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> with RouteAware {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute) routeObserver.subscribe(this, route);
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    super.dispose();
  }

  // Returned to the shell from a pushed route → signal Home to reconnect.
  // The observer callback fires during the navigator's flush phase (still inside
  // a build), so defer the provider mutation to after the frame to avoid
  // "modified a provider while the widget tree was building".
  @override
  void didPopNext() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(homeRefreshTick.notifier).state++;
    });
  }

  void _go(int index) {
    widget.navigationShell.goBranch(
      index,
      // Re-tapping the active tab pops it back to its root.
      initialLocation: index == widget.navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context) {
    final loggedIn = ref.watch(authProvider).isLoggedIn;
    // Drop the request badge on logout so the next account starts clean.
    ref.listen(authProvider.select((s) => s.isLoggedIn), (_, isIn) {
      if (isIn == false) {
        ref.read(pendingRequestsProvider.notifier).clear();
      }
    });
    return Scaffold(
      body: widget.navigationShell,
      bottomNavigationBar: loggedIn ? _bottomBar() : null,
    );
  }

  Widget _bottomBar() {
    final i = widget.navigationShell.currentIndex;
    final pendingRequests = ref.watch(pendingRequestsProvider);
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border, width: 0.5)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 64,
          child: Row(
            children: [
              _NavItem(
                icon: Icons.home_outlined,
                activeIcon: Icons.home,
                label: 'Home',
                selected: i == 0,
                onTap: () => _go(0),
              ),
              _NavItem(
                icon: Icons.search,
                activeIcon: Icons.search,
                label: 'Search',
                selected: i == 1,
                onTap: () => _go(1),
              ),
              _NavItem(
                icon: Icons.person_outline,
                activeIcon: Icons.person,
                label: 'Profile',
                selected: i == 2,
                badgeCount: pendingRequests,
                onTap: () => _go(2),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final int badgeCount; // pending friend requests → red count over the icon

  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.badgeCount = 0,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.primary : AppColors.textSecondary;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(selected ? activeIcon : icon, color: color, size: 24),
                if (badgeCount > 0)
                  Positioned(
                    top: -5,
                    right: -8,
                    child: Container(
                      constraints: const BoxConstraints(minWidth: 16),
                      padding:
                          const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        color: AppColors.error,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppColors.surface, width: 1.5),
                      ),
                      child: Text(
                        badgeCount > 9 ? '9+' : '$badgeCount',
                        textAlign: TextAlign.center,
                        style: AppTextStyles.caption.copyWith(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          height: 1.2,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: AppTextStyles.label.copyWith(
                color: color,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
