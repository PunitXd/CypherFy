import 'package:dio/dio.dart';
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

/// Step 3 of password reset: set a new password. Reached with a one-time
/// [token] — either the ticket from OTP verification (in-app) or the link token
/// from the emailed reset URL (web deep link).
class ResetPasswordScreen extends ConsumerStatefulWidget {
  final String email;
  final String token;
  const ResetPasswordScreen({
    super.key,
    required this.email,
    required this.token,
  });

  @override
  ConsumerState<ResetPasswordScreen> createState() =>
      _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends ConsumerState<ResetPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  final _repo = AuthRepository();
  bool _loading = false;
  String? _error;

  bool get _hasCredentials =>
      widget.email.isNotEmpty && widget.token.isNotEmpty;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await _repo.resetPassword(
        email: widget.email,
        token: widget.token,
        newPassword: _password.text,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(AppStrings.passwordResetDone)),
        );
        context.go(Routes.login);
      }
    } on DioException catch (e) {
      final data = e.response?.data;
      setState(() => _error = (data is Map && data['message'] is String)
          ? data['message'] as String
          : AppStrings.somethingWrong);
    } catch (_) {
      setState(() => _error = AppStrings.somethingWrong);
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
          child: !_hasCredentials
              ? Center(
                  child: Text(
                    AppStrings.invalidCode,
                    style: AppTextStyles.bodySecondary,
                  ),
                )
              : Form(
                  key: _formKey,
                  child: ListView(
                    children: [
                      const SizedBox(height: 24),
                      Text(AppStrings.setNewPassword,
                          style: AppTextStyles.display),
                      const SizedBox(height: 32),
                      AppTextField(
                        label: AppStrings.newPassword,
                        controller: _password,
                        obscure: true,
                        validator: Validators.password,
                      ),
                      const SizedBox(height: 16),
                      AppTextField(
                        label: AppStrings.confirmPassword,
                        controller: _confirm,
                        obscure: true,
                        validator: (v) => v != _password.text
                            ? AppStrings.passwordsDontMatch
                            : null,
                        onSubmitted: (_) => _submit(),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 16),
                        Text(
                          _error!,
                          style: AppTextStyles.bodySecondary
                              .copyWith(color: Colors.redAccent),
                        ),
                      ],
                      const SizedBox(height: 24),
                      AppButton(
                        label: AppStrings.resetPassword,
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
