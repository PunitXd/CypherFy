import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_strings.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/router/app_router.dart';
import '../../../core/utils/validators.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../widgets/common/app_button.dart';
import '../../widgets/common/app_text_field.dart';

/// Step 1 of password reset: request a 6-digit code (and a reset link) by email.
class ForgotPasswordScreen extends ConsumerStatefulWidget {
  /// Optionally prefill the email field (e.g. when a signed-in user reaches
  /// this from Change password).
  final String? initialEmail;
  const ForgotPasswordScreen({super.key, this.initialEmail});

  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _email = TextEditingController(text: widget.initialEmail ?? '');
  final _repo = AuthRepository();
  bool _loading = false;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final email = _email.text.trim();
    setState(() => _loading = true);
    try {
      // Always succeeds (200) regardless of whether the email is registered —
      // anti-enumeration. Move straight to code entry.
      await _repo.forgotPassword(email);
      if (mounted) context.push(Routes.verifyOtp, extra: email);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: ListView(
              children: [
                const SizedBox(height: 24),
                Text(AppStrings.resetPassword, style: AppTextStyles.display),
                const SizedBox(height: 12),
                Text(
                  AppStrings.forgotPasswordSub,
                  style: AppTextStyles.bodySecondary,
                ),
                const SizedBox(height: 32),
                AppTextField(
                  label: AppStrings.email,
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  validator: Validators.email,
                  onSubmitted: (_) => _submit(),
                ),
                const SizedBox(height: 24),
                AppButton(
                  label: AppStrings.sendCode,
                  loading: _loading,
                  onPressed: _submit,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
