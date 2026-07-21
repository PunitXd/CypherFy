import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_strings.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/router/app_router.dart';
import '../../../core/utils/validators.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/common/app_button.dart';
import '../../widgets/common/app_text_field.dart';

/// Change the logged-in user's password (knows current password). Other sessions
/// are revoked server-side; this session stays signed in.
class ChangePasswordScreen extends ConsumerStatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  ConsumerState<ChangePasswordScreen> createState() =>
      _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends ConsumerState<ChangePasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  final _repo = AuthRepository();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _current.dispose();
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
      await _repo.changePassword(
        currentPassword: _current.text,
        newPassword: _password.text,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(AppStrings.passwordChanged)),
        );
        context.pop();
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
      appBar: AppBar(title: const Text(AppStrings.changePassword)),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: ListView(
              children: [
                const SizedBox(height: 8),
                Text(
                  'Enter your current password, then choose a new one.',
                  style: AppTextStyles.bodySecondary,
                ),
                const SizedBox(height: 24),
                AppTextField(
                  label: AppStrings.currentPassword,
                  controller: _current,
                  obscure: true,
                  validator: (v) =>
                      (v == null || v.isEmpty) ? 'Required' : null,
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () {
                      final email = ref.read(authProvider).user?.email;
                      context.push(Routes.forgotPassword, extra: email);
                    },
                    child: Text(
                      AppStrings.forgotPassword,
                      style: AppTextStyles.bodySecondary,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
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
                  label: AppStrings.changePassword,
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
