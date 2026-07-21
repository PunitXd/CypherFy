import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/router/app_router.dart';
import '../../widgets/chat/room_code_card.dart';
import '../../widgets/chat/ttl_timer.dart';
import '../../widgets/common/app_avatar.dart';

/// "Room info" page for an ephemeral group room. Reached by tapping the chat
/// header. Shows the room code prominently plus live membership and settings.
///
/// It watches the *same* chat provider the chat screen created, so the member
/// roster and count update live while this page is open.
class RoomDetailScreen extends ConsumerWidget {
  final RoomDetailArgs args;
  const RoomDetailScreen({super.key, required this.args});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chat = ref.watch(args.provider);
    final room = args.chat;
    final members = chat.members;
    final count = members.length;

    return Scaffold(
      appBar: AppBar(title: const Text('Room info')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          // ---- Header: identity ----
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
            child: Column(
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.surfaceContainerHigh,
                    border: Border.all(color: AppColors.border, width: 0.5),
                  ),
                  child: Icon(Icons.shield, size: 34, color: AppColors.primary),
                ),
                const SizedBox(height: 14),
                Text(
                  room.title ?? 'Cypher Room',
                  style: AppTextStyles.heading,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                Text('Ephemeral group room',
                    style: AppTextStyles.bodySecondary),
                const SizedBox(height: 8),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.lock, size: 13, color: AppColors.teal),
                    const SizedBox(width: 5),
                    Text('End-to-end encrypted',
                        style: AppTextStyles.caption
                            .copyWith(color: AppColors.teal)),
                  ],
                ),
              ],
            ),
          ),

          // ---- Room code (prominent) ----
          if (room.code != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
              child: RoomCodeCard(
                code: room.code!,
                expiresAt: room.expiresAt,
                heading: 'Room code',
                subheading: 'Share this code to invite people',
              ),
            ),

          // ---- Details ----
          const _SectionHeader('Details'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border, width: 0.5),
              ),
              child: Column(
                children: [
                  _InfoRow(
                    icon: Icons.group,
                    iconColor: AppColors.primary,
                    title: 'Members',
                    trailing: '$count ${count == 1 ? 'person' : 'people'}',
                  ),
                  const Divider(height: 0.5),
                  if (room.expiresAt != null) ...[
                    _InfoRow(
                      icon: Icons.timer_outlined,
                      iconColor: AppColors.textSecondary,
                      title: 'Expires in',
                      trailingWidget: TtlTimer(expiresAt: room.expiresAt!),
                    ),
                    const Divider(height: 0.5),
                  ],
                  _InfoRow(
                    icon: room.isLocked ? Icons.lock : Icons.lock_open,
                    iconColor:
                        room.isLocked ? AppColors.amber : AppColors.textSecondary,
                    title: room.isLocked ? 'Locked' : 'Open',
                    subtitle: room.isLocked
                        ? 'New members must knock to enter'
                        : 'Anyone with the code can join',
                  ),
                  if (args.myAlias != null) ...[
                    const Divider(height: 0.5),
                    _InfoRow(
                      icon: Icons.badge_outlined,
                      iconColor: AppColors.textSecondary,
                      title: 'Your alias',
                      trailing: args.myAlias,
                    ),
                  ],
                  if (room.isHost) ...[
                    const Divider(height: 0.5),
                    _InfoRow(
                      icon: Icons.star_outline,
                      iconColor: AppColors.amber,
                      title: 'You are the host',
                      subtitle: 'You can end this room for everyone',
                    ),
                  ],
                  const Divider(height: 0.5),
                  InkWell(
                    onTap: () => context.push(Routes.encryptionInfo),
                    child: _InfoRow(
                      icon: Icons.enhanced_encryption_outlined,
                      iconColor: AppColors.teal,
                      title: 'Encryption',
                      subtitle: 'Key derived from the code (PBKDF2)',
                      chevron: true,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ---- Member roster ----
          _SectionHeader('Members · $count'),
          if (members.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
              child: Text('Just you so far',
                  style: AppTextStyles.bodySecondary),
            )
          else
            ...members.map((m) {
              final isYou = m.alias == args.myAlias;
              return ListTile(
                leading: AppAvatar(name: m.alias, size: 40),
                title: Text(m.alias, style: AppTextStyles.body),
                trailing: isYou
                    ? Text('You',
                        style: AppTextStyles.caption
                            .copyWith(color: AppColors.primary))
                    : null,
              );
            }),
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
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 6),
        child: Text(
          label.toUpperCase(),
          style: AppTextStyles.monoLabel.copyWith(
            color: AppColors.textSecondary,
            letterSpacing: 1.5,
          ),
        ),
      );
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String? subtitle;
  final String? trailing;
  final Widget? trailingWidget;
  final bool chevron;

  const _InfoRow({
    required this.icon,
    required this.iconColor,
    required this.title,
    this.subtitle,
    this.trailing,
    this.trailingWidget,
    this.chevron = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Row(
        children: [
          Icon(icon, size: 20, color: iconColor),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTextStyles.body),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(subtitle!, style: AppTextStyles.caption),
                ],
              ],
            ),
          ),
          if (trailingWidget != null)
            trailingWidget!
          else if (trailing != null)
            Text(trailing!, style: AppTextStyles.bodySecondary),
          if (chevron) ...[
            const SizedBox(width: 4),
            Icon(Icons.chevron_right, size: 18, color: AppColors.textMuted),
          ],
        ],
      ),
    );
  }
}
