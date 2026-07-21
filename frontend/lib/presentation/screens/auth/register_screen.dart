import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_strings.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/router/app_router.dart';
import '../../../core/utils/validators.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/common/app_button.dart';
import '../../widgets/common/app_text_field.dart';
import '../../widgets/common/google_sign_in_button.dart';
import '../../widgets/common/or_divider.dart';

/// Full-screen registration form.
class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _displayName = TextEditingController();
  final _username = TextEditingController();

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _displayName.dispose();
    _username.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final email = _email.text.trim();
    final password = _password.text;
    final ok = await ref.read(authProvider.notifier).register(
          email: email,
          password: password,
          displayName: _displayName.text.trim(),
          username: _username.text.trim().toLowerCase(),
        );
    // A code was emailed — finish sign-up on the verification screen.
    if (ok && mounted) {
      context.push(
        Routes.verifyEmail,
        extra: EmailVerifyArgs(email: email, password: password),
      );
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
                const SizedBox(height: 16),
                Text(AppStrings.register, style: AppTextStyles.display),
                const SizedBox(height: 32),
                AppTextField(
                  label: AppStrings.displayName,
                  controller: _displayName,
                  textCapitalization: TextCapitalization.words,
                  validator: (v) => Validators.required(v, 'Display name'),
                ),
                const SizedBox(height: 16),
                AppTextField(
                  label: AppStrings.username,
                  controller: _username,
                  validator: Validators.username,
                ),
                const SizedBox(height: 16),
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
                if (auth.error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(auth.error!,
                        style: AppTextStyles.bodySecondary
                            .copyWith(color: Colors.redAccent)),
                  ),
                const SizedBox(height: 24),
                AppButton(
                  label: AppStrings.register,
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
                    onPressed: () => context.pop(),
                    child: const Text(AppStrings.haveAccount),
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
