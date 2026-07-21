import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/router/app_router.dart';
import '../../../core/utils/alias_generator.dart';
import '../../providers/room_provider.dart';
import '../../widgets/common/app_button.dart';
import '../../widgets/common/app_text_field.dart';
import '../../widgets/common/field_label.dart';

/// Join an ephemeral room by its 6-character code — the ONLY thing needed.
///
/// The encryption key is derived from this same code locally (PBKDF2) on both
/// the creator's and joiner's devices, so no URL or key is ever required.
class JoinRoomScreen extends ConsumerStatefulWidget {
  const JoinRoomScreen({super.key});

  @override
  ConsumerState<JoinRoomScreen> createState() => _JoinRoomScreenState();
}

class _JoinRoomScreenState extends ConsumerState<JoinRoomScreen> {
  static const _len = 6;
  final _controllers = List.generate(_len, (_) => TextEditingController());
  final _nodes = List.generate(_len, (_) => FocusNode());
  final _name = TextEditingController();
  bool _joining = false;
  String? _error;

  String get _code => _controllers.map((c) => c.text).join();
  bool get _complete => _code.length == _len;

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    for (final n in _nodes) {
      n.dispose();
    }
    _name.dispose();
    super.dispose();
  }

  void _onChanged(int i, String v) {
    // Clear any error the moment the user edits again.
    if (_error != null) setState(() => _error = null);

    final cleaned = v.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

    if (cleaned.length > 1) {
      // The user pasted the whole code at once → spread it across every box from
      // the start. (The boxes intentionally have no maxLength, otherwise a paste
      // would be clipped to a single character and never reach this branch.)
      for (var j = 0; j < _len; j++) {
        _controllers[j].text = j < cleaned.length ? cleaned[j] : '';
      }
      final focus = cleaned.length.clamp(1, _len) - 1;
      _nodes[focus].requestFocus();
    } else {
      // Single character → keep just it in this box and advance.
      _controllers[i].text = cleaned;
      _controllers[i].selection =
          TextSelection.collapsed(offset: cleaned.length);
      if (cleaned.isNotEmpty && i < _len - 1) _nodes[i + 1].requestFocus();
    }
    setState(() {});
    if (_complete) _tryJoin();
  }

  KeyEventResult _onKey(int i, FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.backspace &&
        _controllers[i].text.isEmpty &&
        i > 0) {
      _controllers[i - 1].clear();
      _nodes[i - 1].requestFocus();
      setState(() {});
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Future<void> _tryJoin() async {
    final code = _code.toUpperCase().trim();
    if (code.length != _len || _joining) return;

    setState(() {
      _joining = true;
      _error = null;
    });
    try {
      // 1. Validate the code exists / hasn't expired before opening the chat.
      final room = await ref.read(roomProvider.notifier).validateCode(code);

      // 2. The key is derived from the code inside the chat screen. The joiner
      //    may pick a display name; if they leave it blank we assign a random
      //    anonymous alias. Locked rooms route through the knock flow in-chat.
      if (!mounted) return;
      final chosen = _name.text.trim();
      context.pushReplacement(
        Routes.chat,
        extra: ChatArgs(
          isEphemeral: true,
          code: room.code,
          title: room.name,
          isHost: false,
          expiresAt: room.expiresAt,
          alias: chosen.isNotEmpty ? chosen : AliasGenerator.generate(),
          isLocked: room.isLocked,
        ),
      );
    } catch (_) {
      setState(() {
        _error = 'Room not found';
        _joining = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Container(
                padding: const EdgeInsets.all(40),
                decoration: BoxDecoration(
                  color: AppColors.surfaceContainer,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border, width: 0.5),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Icon frame.
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.surfaceContainerHigh,
                        border:
                            Border.all(color: AppColors.border, width: 0.5),
                      ),
                      child: Icon(Icons.vpn_key_outlined,
                          color: AppColors.primary, size: 28),
                    ),
                    const SizedBox(height: 24),
                    Text('Enter room code',
                        style: AppTextStyles.display, textAlign: TextAlign.center),
                    const SizedBox(height: 8),
                    Text(
                      'Ask the room creator for their 6-character code',
                      style: AppTextStyles.bodySecondary,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 28),
                    // Optional display name — blank means join anonymously with a
                    // randomly generated alias.
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: FieldLabel('Your name (optional)'),
                    ),
                    const SizedBox(height: 8),
                    AppTextField(
                      controller: _name,
                      hint: 'Leave blank to stay anonymous',
                      maxLength: 24,
                      textCapitalization: TextCapitalization.words,
                      onSubmitted: (_) => _nodes.first.requestFocus(),
                    ),
                    const SizedBox(height: 20),
                    _buildBoxes(),
                    const SizedBox(height: 16),
                    // Error / spacer.
                    SizedBox(
                      height: 24,
                      child: _error == null
                          ? null
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.error_outline,
                                    size: 16, color: AppColors.error),
                                const SizedBox(width: 6),
                                Text(_error!,
                                    style: AppTextStyles.label
                                        .copyWith(color: AppColors.error)),
                              ],
                            ),
                    ),
                    const SizedBox(height: 8),
                    AppButton(
                      label: 'Join room',
                      loading: _joining,
                      onPressed: _complete ? _tryJoin : null,
                    ),
                    const SizedBox(height: 24),
                    TextButton(
                      onPressed: () => context.pop(),
                      child: Text('Back to dashboard',
                          style: AppTextStyles.label),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBoxes() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < _len; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          _CodeBox(
            controller: _controllers[i],
            focusNode: _nodes[i],
            error: _error != null,
            onChanged: (v) => _onChanged(i, v),
            onKey: (node, event) => _onKey(i, node, event),
          ),
        ],
      ],
    );
  }
}

class _CodeBox extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool error;
  final ValueChanged<String> onChanged;
  final KeyEventResult Function(FocusNode, KeyEvent) onKey;

  const _CodeBox({
    required this.controller,
    required this.focusNode,
    required this.error,
    required this.onChanged,
    required this.onKey,
  });

  @override
  Widget build(BuildContext context) {
    final borderColor = error ? AppColors.error : AppColors.border;
    return SizedBox(
      width: 48,
      height: 56,
      child: Focus(
        onKeyEvent: onKey,
        child: TextField(
          controller: controller,
          focusNode: focusNode,
          onChanged: onChanged,
          textAlign: TextAlign.center,
          // No maxLength: it would clip a pasted code to one char. _onChanged
          // keeps each box to a single character and distributes a paste.
          keyboardType: TextInputType.text,
          textCapitalization: TextCapitalization.characters,
          style: AppTextStyles.code.copyWith(
            fontSize: 22,
            letterSpacing: 0,
            color: error ? AppColors.error : AppColors.textPrimary,
          ),
          decoration: InputDecoration(
            counterText: '',
            filled: true,
            fillColor: AppColors.surface,
            contentPadding: EdgeInsets.zero,
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: borderColor, width: 0.5),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(
                  color: error ? AppColors.error : AppColors.primary, width: 1),
            ),
          ),
        ),
      ),
    );
  }
}
