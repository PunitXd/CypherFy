import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_strings.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/router/app_router.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/common/app_button.dart';
import '../../widgets/common/otp_input.dart';

/// Registration step 2: enter the 6-digit code emailed to [email]. On success
/// the account is verified, tokens are issued, and we land on Home. [password]
/// is carried through so the session's wrapping key can be derived on verify.
class VerifyEmailScreen extends ConsumerStatefulWidget {
  final String email;
  final String password;
  const VerifyEmailScreen({
    super.key,
    required this.email,
    required this.password,
  });

  @override
  ConsumerState<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends ConsumerState<VerifyEmailScreen> {
  final _otp = TextEditingController();
  bool _loading = false;
  bool _resending = false;
  String? _error;
  Timer? _cooldownTimer;
  int _cooldownLeft = 0;

  @override
  void initState() {
    super.initState();
    // A code was just sent on the register/login step — start the resend timer.
    _startCooldown();
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _otp.dispose();
    super.dispose();
  }

  void _startCooldown([int seconds = 30]) {
    _cooldownTimer?.cancel();
    setState(() => _cooldownLeft = seconds);
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() => _cooldownLeft--);
      if (_cooldownLeft <= 0) t.cancel();
    });
  }

  Future<void> _verify() async {
    final code = _otp.text.trim();
    if (code.length != 6) {
      setState(() => _error = AppStrings.invalidCode);
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    final ok = await ref.read(authProvider.notifier).verifyEmail(
          email: widget.email,
          otp: code,
          password: widget.password,
        );
    if (!mounted) return;
    if (ok) {
      context.go(Routes.home);
    } else {
      setState(() {
        _loading = false;
        _error = ref.read(authProvider).error ?? AppStrings.invalidCode;
      });
    }
  }

  Future<void> _resend() async {
    setState(() {
      _resending = true;
      _error = null;
    });
    await ref.read(authProvider.notifier).resendVerification(widget.email);
    _otp.clear();
    if (mounted) {
      _startCooldown();
      setState(() => _resending = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(AppStrings.codeResent)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ListView(
            children: [
              const SizedBox(height: 24),
              Text('Verify your email', style: AppTextStyles.display),
              const SizedBox(height: 12),
              Text.rich(
                TextSpan(
                  style: AppTextStyles.bodySecondary,
                  children: [
                    const TextSpan(text: '${AppStrings.codeSentTo} '),
                    TextSpan(text: widget.email, style: AppTextStyles.body),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              OtpInput(
                controller: _otp,
                onChanged: (_) {
                  if (_error != null) setState(() => _error = null);
                },
                onCompleted: (_) => _verify(),
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
                label: AppStrings.verify,
                loading: _loading,
                onPressed: _verify,
              ),
              const SizedBox(height: 8),
              Center(
                child: TextButton(
                  onPressed:
                      (_resending || _cooldownLeft > 0) ? null : _resend,
                  child: Text(
                    _resending
                        ? '…'
                        : _cooldownLeft > 0
                            ? 'Resend code in ${_cooldownLeft}s'
                            : AppStrings.resendCode,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
