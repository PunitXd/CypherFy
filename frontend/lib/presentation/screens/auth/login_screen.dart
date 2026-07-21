import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_strings.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/router/app_router.dart';
import '../../../core/utils/validators.dart';
import '../../providers/auth_provider.dart';
import '../../providers/room_provider.dart';
import '../../widgets/common/app_button.dart';
import '../../widgets/common/app_text_field.dart';
import '../../widgets/common/google_sign_in_button.dart';
import '../../widgets/common/or_divider.dart';

/// Full-screen login form.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final email = _email.text.trim();
    final password = _password.text;
    final result =
        await ref.read(authProvider.notifier).login(email, password);
    if (!mounted) return;
    switch (result) {
      case LoginResult.success:
        await ref.read(roomProvider.notifier).loadPermanent();
        if (mounted) context.go(Routes.home);
      case LoginResult.needsVerification:
        // Unverified account — a fresh code was emailed; finish verifying.
        context.push(
          Routes.verifyEmail,
          extra: EmailVerifyArgs(email: email, password: password),
        );
      case LoginResult.failed:
        break; // error is surfaced via auth state
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
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
                Text(AppStrings.login, style: AppTextStyles.display),
                const SizedBox(height: 32),
                AppTextField(
                  label: AppStrings.email,
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  validator: Validators.email,
                ),
                const SizedBox(height: 16),
                AppTextField(
                  label: AppStrings.password,
                  controller: _password,
                  obscure: true,
                  validator: Validators.password,
                  onSubmitted: (_) => _submit(),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => context.push(Routes.forgotPassword),
                    child: const Text(AppStrings.forgotPassword),
                  ),
                ),
                if (auth.error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(auth.error!,
                        style: AppTextStyles.bodySecondary
                            .copyWith(color: Colors.redAccent)),
                  ),
                const SizedBox(height: 8),
                AppButton(
                  label: AppStrings.login,
                  loading: auth.loading,
                  onPressed: _submit,
                ),
                const SizedBox(height: 20),
                const OrDivider(),
                const SizedBox(height: 20),
                const GoogleSignInButton(),
                const SizedBox(height: 16),
                Center(
                  child: TextButton(
                    onPressed: () => context.push(Routes.register),
                    child: const Text(AppStrings.noAccount),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
