import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/router/app_router.dart';
import '../../../core/utils/alias_generator.dart';
import '../../../data/models/room_model.dart';
import '../../providers/room_provider.dart';
import '../../widgets/common/app_button.dart';
import '../../widgets/common/app_text_field.dart';
import '../../widgets/common/select_pill.dart';
import '../../widgets/common/field_label.dart';
import '../../widgets/chat/room_code_card.dart';

/// Create an ephemeral room. The shareable item is just the 6-char code — the
/// encryption key is DERIVED from that code on each device (no key in any URL).
class CreateRoomScreen extends ConsumerStatefulWidget {
  const CreateRoomScreen({super.key});

  @override
  ConsumerState<CreateRoomScreen> createState() => _CreateRoomScreenState();
}

class _CreateRoomScreenState extends ConsumerState<CreateRoomScreen> {
  final _name = TextEditingController(text: 'Cypher Room');
  int _maxUsers = 2;
  bool _locked = false;
  String _ttl = '1h';
  bool _loading = false;

  // Participant presets, mirroring the Stitch "Max Participants" pills.
  static const _participantOptions = [2, 3, 4, 5, 6, 8, 10];

  // TTL presets mirror backend ROOM.TTL_OPTIONS.
  static const _ttlOptions = {
    '1h': 3600,
    '6h': 21600,
    '24h': 86400,
    '7d': 604800,
  };
  static const _ttlLabels = {
    '1h': '1 hour',
    '6h': '6 hours',
    '24h': '24 hours',
    '7d': '7 days',
  };

  RoomModel? _created;
  // The host's alias, kept so the SAME identity is used to enter the room —
  // this is what the server stores as createdBy and checks for host actions.
  String? _hostAlias;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    setState(() => _loading = true);
    try {
      // The host gets a random alias; the server allocates the 6-char code.
      // No key is generated here — it will be derived from the code on entry.
      final alias = AliasGenerator.generate();

      final room = await ref.read(roomProvider.notifier).createEphemeral(
            alias: alias,
            name: _name.text.trim(),
            maxUsers: _maxUsers,
            ttlSeconds: _ttlOptions[_ttl]!,
            isLocked: _locked,
          );

      setState(() {
        _created = room;
        _hostAlias = alias;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to create room: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('New room')),
      body: SafeArea(
        child: _created == null ? _buildForm() : _buildCreated(),
      ),
    );
  }

  Widget _buildForm() {
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 32, 20, 24),
            children: [
              // Room name.
              const FieldLabel('Room Identification'),
              const SizedBox(height: 8),
              AppTextField(
                controller: _name,
                hint: 'Enter room name...',
                textCapitalization: TextCapitalization.words,
              ),
              const SizedBox(height: 32),

              // Max participants.
              FieldLabel(
                'Max Participants',
                trailing: '$_maxUsers members',
              ),
              const SizedBox(height: 12),
              SelectPillGroup<int>(
                value: _maxUsers,
                options: [
                  for (final n in _participantOptions)
                    SelectPillOption(value: n, label: '$n'),
                ],
                onChanged: (v) => setState(() => _maxUsers = v),
              ),
              const SizedBox(height: 32),

              // Auto-delete.
              FieldLabel(
                'Auto-delete After',
                trailing: _ttlLabels[_ttl],
              ),
              const SizedBox(height: 12),
              SelectPillGroup<String>(
                value: _ttl,
                options: [
                  for (final t in _ttlOptions.keys)
                    SelectPillOption(value: t, label: t),
                ],
                onChanged: (v) => setState(() => _ttl = v),
              ),
              const SizedBox(height: 24),

              // Lock room toggle card.
              _LockRoomCard(
                value: _locked,
                onChanged: (v) => setState(() => _locked = v),
              ),
            ],
          ),
        ),
        // Bottom action area.
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: AppColors.border, width: 0.5)),
          ),
          child: AppButton(
            label: 'Create room',
            icon: Icons.add_circle_outline,
            loading: _loading,
            onPressed: _create,
          ),
        ),
      ],
    );
  }

  Widget _buildCreated() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        RoomCodeCard(code: _created!.code!, expiresAt: _created!.expiresAt),
        const SizedBox(height: 24),
        AppButton(
          label: 'Enter room',
          icon: Icons.arrow_forward,
          onPressed: () => context.pushReplacement(
            Routes.chat,
            extra: ChatArgs(
              isEphemeral: true,
              code: _created!.code,
              title: _created!.name,
              isHost: true,
              expiresAt: _created!.expiresAt,
              alias: _hostAlias, // same identity the server stored as createdBy
              isLocked: _locked,
            ),
          ),
        ),
      ],
    );
  }
}

/// Bordered "Lock room" card with an icon, subtitle and trailing switch —
/// mirrors the Stitch lock-room surface.
class _LockRoomCard extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;

  const _LockRoomCard({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.border, width: 0.5),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        value ? Icons.lock : Icons.lock_open,
                        size: 20,
                        color: value
                            ? AppColors.primary
                            : AppColors.textSecondary,
                      ),
                      const SizedBox(width: 8),
                      Text('Lock room', style: AppTextStyles.subheading),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text('Members must knock to enter',
                      style: AppTextStyles.bodySecondary),
                ],
              ),
            ),
            Switch(value: value, onChanged: onChanged),
          ],
        ),
      ),
    );
  }
}
