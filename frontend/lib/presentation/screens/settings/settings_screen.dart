import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/router/app_router.dart';
import '../../../data/models/user_model.dart';
import '../../../data/repositories/user_repository.dart';
import '../../providers/auth_provider.dart';
import '../../providers/push_provider.dart';
import '../../providers/theme_provider.dart';
import '../../widgets/common/app_avatar.dart';

/// App settings. Phase 1: Account (edit profile, change password), Appearance
/// (theme), About, and Log out. Notifications / Privacy / Delete account are
/// added in a later phase and slot into the sections below.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider).user;
    final isDark = ref.watch(themeProvider);

    return Scaffold(
      appBar: AppBar(title: const Text(AppStrings.settings)),
      body: ListView(
        children: [
          // ── Account header ──────────────────────────────────────────────
          if (user != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                children: [
                  AppAvatar(
                    name: user.displayName,
                    imageUrl: user.avatar,
                    size: 56,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(user.displayName,
                            style: AppTextStyles.heading,
                            overflow: TextOverflow.ellipsis),
                        Text('@${user.username}',
                            style: AppTextStyles.bodySecondary),
                        if (user.email != null && user.email!.isNotEmpty)
                          Text(user.email!,
                              style: AppTextStyles.caption,
                              overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                ],
              ),
            ),

          // ── Account ─────────────────────────────────────────────────────
          const _SectionHeader(AppStrings.account),
          _Tile(
            icon: Icons.edit_outlined,
            title: AppStrings.editProfile,
            onTap: () => context.push(Routes.editProfile),
          ),
          _Tile(
            icon: Icons.lock_outline,
            title: AppStrings.changePassword,
            onTap: () => context.push(Routes.changePassword),
          ),

          // ── Appearance ──────────────────────────────────────────────────
          const _SectionHeader(AppStrings.appearance),
          SwitchListTile(
            secondary: const Icon(Icons.dark_mode_outlined),
            title: Text(AppStrings.darkMode, style: AppTextStyles.body),
            subtitle:
                Text(AppStrings.darkModeSub, style: AppTextStyles.caption),
            value: isDark,
            activeThumbColor: AppColors.primary,
            onChanged: (v) => ref.read(themeProvider.notifier).setDark(v),
          ),

          // ── Notifications ───────────────────────────────────────────────
          const _SectionHeader(AppStrings.notifications),
          SwitchListTile(
            secondary: const Icon(Icons.notifications_outlined),
            title:
                Text(AppStrings.pushNotifications, style: AppTextStyles.body),
            subtitle: Text(AppStrings.pushNotificationsSub,
                style: AppTextStyles.caption),
            value: ref.watch(pushProvider),
            activeThumbColor: AppColors.primary,
            onChanged: (v) => ref.read(pushProvider.notifier).setEnabled(v),
          ),
          _PrivacySwitch(
            icon: Icons.call_outlined,
            title: AppStrings.receiveCalls,
            subtitle: AppStrings.receiveCallsSub,
            value: user?.receiveCalls ?? true,
            update: (repo, v) => repo.updatePrivacy(receiveCalls: v),
          ),

          // ── Privacy ─────────────────────────────────────────────────────
          const _SectionHeader(AppStrings.privacy),
          _PrivacySwitch(
            icon: Icons.circle_outlined,
            title: AppStrings.showOnlineStatus,
            subtitle: AppStrings.showOnlineStatusSub,
            value: user?.showOnlineStatus ?? true,
            update: (repo, v) => repo.updatePrivacy(showOnlineStatus: v),
          ),
          _PrivacySwitch(
            icon: Icons.schedule_outlined,
            title: AppStrings.showLastSeen,
            subtitle: AppStrings.showLastSeenSub,
            value: user?.showLastSeen ?? true,
            update: (repo, v) => repo.updatePrivacy(showLastSeen: v),
          ),

          // ── About ───────────────────────────────────────────────────────
          const _SectionHeader(AppStrings.about),
          _Tile(
            icon: Icons.shield_outlined,
            title: AppStrings.howEncryptionWorks,
            onTap: () => context.push(Routes.encryptionInfo),
          ),
          _Tile(
            icon: Icons.description_outlined,
            title: AppStrings.licenses,
            onTap: () => showLicensePage(
              context: context,
              applicationName: AppStrings.appName,
            ),
          ),
          const _VersionTile(),

          const Divider(height: 32),

          // ── Danger zone ─────────────────────────────────────────────────
          _Tile(
            icon: Icons.logout,
            title: AppStrings.logout,
            danger: true,
            onTap: () async {
              await ref.read(authProvider.notifier).logout();
              if (context.mounted) context.go(Routes.home);
            },
          ),
          _Tile(
            icon: Icons.delete_forever_outlined,
            title: AppStrings.deleteAccount,
            danger: true,
            onTap: () => context.push(Routes.deleteAccount),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String label;
  const _SectionHeader(this.label);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 6),
        child: Text(
          label.toUpperCase(),
          style: AppTextStyles.monoLabel.copyWith(
            color: AppColors.textSecondary,
            letterSpacing: 1.5,
          ),
        ),
      );
}

class _Tile extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;
  final bool danger;
  const _Tile({
    required this.icon,
    required this.title,
    required this.onTap,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = danger ? AppColors.error : AppColors.textPrimary;
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(title, style: AppTextStyles.body.copyWith(color: color)),
      trailing: danger
          ? null
          : Icon(Icons.chevron_right, color: AppColors.textMuted),
      onTap: onTap,
    );
  }
}

/// A privacy toggle backed by the server. Updates optimistically, syncs the
/// returned user into auth state, and reverts on failure.
class _PrivacySwitch extends ConsumerStatefulWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final Future<UserModel> Function(UserRepository repo, bool value) update;

  const _PrivacySwitch({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.update,
  });

  @override
  ConsumerState<_PrivacySwitch> createState() => _PrivacySwitchState();
}

class _PrivacySwitchState extends ConsumerState<_PrivacySwitch> {
  late bool _value = widget.value;
  bool _busy = false;

  @override
  void didUpdateWidget(covariant _PrivacySwitch old) {
    super.didUpdateWidget(old);
    // Keep in sync with the source-of-truth user unless a write is in flight.
    if (!_busy && widget.value != _value) _value = widget.value;
  }

  Future<void> _toggle(bool v) async {
    final prev = _value;
    setState(() {
      _value = v;
      _busy = true;
    });
    try {
      final user = await widget.update(UserRepository(), v);
      ref.read(authProvider.notifier).setUser(user);
    } catch (_) {
      if (mounted) {
        setState(() => _value = prev);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(AppStrings.somethingWrong)),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      secondary: Icon(widget.icon),
      title: Text(widget.title, style: AppTextStyles.body),
      subtitle: Text(widget.subtitle, style: AppTextStyles.caption),
      value: _value,
      activeThumbColor: AppColors.primary,
      onChanged: _busy ? null : _toggle,
    );
  }
}

class _VersionTile extends StatelessWidget {
  const _VersionTile();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PackageInfo>(
      future: PackageInfo.fromPlatform(),
      builder: (context, snap) {
        final v = snap.hasData
            ? '${snap.data!.version} (${snap.data!.buildNumber})'
            : '—';
        return ListTile(
          leading: const Icon(Icons.info_outline),
          title: Text(AppStrings.version, style: AppTextStyles.body),
          trailing: Text(v, style: AppTextStyles.bodySecondary),
        );
      },
    );
  }
}
