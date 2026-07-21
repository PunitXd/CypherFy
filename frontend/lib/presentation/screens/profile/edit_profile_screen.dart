import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../data/repositories/user_repository.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/common/app_avatar.dart';
import '../../widgets/common/app_text_field.dart';
import '../../widgets/common/field_label.dart';

/// Edit the logged-in user's profile — display name, username, and bio. The
/// username can be changed at most once every 30 days (enforced server-side).
/// "Change photo" picks an image and uploads it to the backend (→ R2).
class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key});

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  final _repo = UserRepository();
  late final TextEditingController _name;
  late final TextEditingController _bio;
  late final TextEditingController _username;
  bool _saving = false;
  bool _uploadingAvatar = false;

  @override
  void initState() {
    super.initState();
    final user = ref.read(authProvider).user;
    _name = TextEditingController(text: user?.displayName ?? '');
    _bio = TextEditingController(text: user?.bio ?? '');
    _username = TextEditingController(text: user?.username ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _bio.dispose();
    _username.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final canChange = ref.read(authProvider).user?.canChangeUsername ?? false;
      final updated = await _repo.updateProfile(
        displayName: _name.text.trim(),
        bio: _bio.text.trim(),
        // Only send the username when it's actually editable, lowercased to
        // match the server's rules.
        username: canChange ? _username.text.trim().toLowerCase() : null,
      );
      ref.read(authProvider.notifier).setUser(updated);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Profile updated')));
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(_errorMessage(e))));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickAvatar() async {
    if (_uploadingAvatar) return;
    final picker = ImagePicker();
    final xfile = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 85,
    );
    if (xfile == null) return;
    setState(() => _uploadingAvatar = true);
    try {
      final bytes = await xfile.readAsBytes();
      await _repo.uploadAvatar(bytes, xfile.name, xfile.mimeType);
      // The backend saved the new URL — refresh the user so it shows everywhere.
      final updated = await _repo.getMe();
      ref.read(authProvider.notifier).setUser(updated);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Photo updated')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(_errorMessage(e))));
      }
    } finally {
      if (mounted) setState(() => _uploadingAvatar = false);
    }
  }

  // Surface the server's specific message ("already taken", "change again in
  // N days") instead of a raw exception.
  String _errorMessage(Object e) {
    if (e is DioException) {
      final data = e.response?.data;
      if (data is Map && data['message'] is String) {
        return data['message'] as String;
      }
    }
    return 'Could not save. Please try again.';
  }

  static String _formatDate(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final l = d.toLocal();
    return '${months[l.month - 1]} ${l.day}, ${l.year}';
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider).user;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => context.pop(),
        ),
        title: Text('Edit profile', style: AppTextStyles.subheading),
        centerTitle: true,
        actions: [
          _saving
              ? const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20),
                  child: Center(
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                )
              : TextButton(
                  onPressed: _save,
                  child: Text('Save',
                      style: AppTextStyles.label.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w600)),
                ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 32, 20, 24),
        children: [
          // Avatar + change photo.
          Center(
            child: Column(
              children: [
                Stack(
                  alignment: Alignment.bottomRight,
                  children: [
                    AppAvatar(
                      name: user?.displayName ?? '?',
                      imageUrl: user?.avatar,
                      size: 96,
                    ),
                    GestureDetector(
                      onTap: _uploadingAvatar ? null : _pickAvatar,
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.primary,
                          border:
                              Border.all(color: AppColors.surface, width: 2),
                        ),
                        child: _uploadingAvatar
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.photo_camera,
                                size: 16, color: Colors.white),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _uploadingAvatar ? null : _pickAvatar,
                  child: Text(_uploadingAvatar ? 'Uploading…' : 'Change photo',
                      style: AppTextStyles.label
                          .copyWith(color: AppColors.primary)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          const FieldLabel('Display Name'),
          const SizedBox(height: 8),
          AppTextField(
            controller: _name,
            hint: 'Enter your display name',
            textCapitalization: TextCapitalization.words,
          ),
          const SizedBox(height: 24),

          const FieldLabel('Username'),
          const SizedBox(height: 8),
          Builder(builder: (context) {
            final canChange = user?.canChangeUsername ?? false;
            return TextFormField(
              controller: _username,
              readOnly: !canChange,
              autocorrect: false,
              enableSuggestions: false,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9_]')),
                LengthLimitingTextInputFormatter(20),
              ],
              style: AppTextStyles.body.copyWith(
                color: canChange ? null : AppColors.textSecondary,
              ),
              decoration: const InputDecoration(prefixText: '@ '),
            );
          }),
          const SizedBox(height: 4),
          Builder(builder: (context) {
            final canChange = user?.canChangeUsername ?? false;
            final readyAt = user?.usernameChangeableAt;
            final text = canChange
                ? 'You can change your username once every 30 days.'
                : 'You can change your username again on '
                    '${readyAt != null ? _formatDate(readyAt) : 'a later date'}.';
            return Text(text, style: AppTextStyles.caption);
          }),
          const SizedBox(height: 24),

          const FieldLabel('Bio'),
          const SizedBox(height: 8),
          AppTextField(
            controller: _bio,
            hint: 'A brief description...',
            maxLength: 160,
            minLines: 3,
            maxLines: 5,
          ),
        ],
      ),
    );
  }
}
