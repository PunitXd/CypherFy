import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_strings.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/router/app_router.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../widgets/common/app_button.dart';
import '../../widgets/common/otp_input.dart';

/// Step 2 of password reset: enter the 6-digit code emailed to [email]. On
/// success we exchange it for a one-time ticket and move to the new-password
/// screen.
class VerifyOtpScreen extends ConsumerStatefulWidget {
  final String email;
  const VerifyOtpScreen({super.key, required this.email});

  @override
  ConsumerState<VerifyOtpScreen> createState() => _VerifyOtpScreenState();
}

class _VerifyOtpScreenState extends ConsumerState<VerifyOtpScreen> {
  final _otp = TextEditingController();
  final _repo = AuthRepository();
  bool _loading = false;
  bool _resending = false;
  String? _error;
  Timer? _cooldownTimer;
  int _cooldownLeft = 0;

  @override
  void initState() {
    super.initState();
    // A code was just sent on the previous screen — start the resend cooldown.
    _startCooldown();
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _otp.dispose();
    super.dispose();
  }

  /// Disable "Resend code" for [seconds], counting down once per second.
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
    try {
      final ticket = await _repo.verifyOtp(email: widget.email, otp: code);
      if (mounted) {
        context.push(
          Routes.resetPassword,
          extra: {'email': widget.email, 'token': ticket},
        );
      }
    } on DioException catch (e) {
      setState(() => _error = _messageFrom(e));
    } catch (_) {
      setState(() => _error = AppStrings.somethingWrong);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resend() async {
    setState(() {
      _resending = true;
      _error = null;
    });
    try {
      await _repo.forgotPassword(widget.email);
      _otp.clear();
      if (mounted) {
        _startCooldown();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(AppStrings.codeResent)),
        );
      }
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  /// Prefer the server's message (e.g. "Too many attempts…") over a generic one.
  String _messageFrom(DioException e) {
    final data = e.response?.data;
    if (data is Map && data['message'] is String) return data['message'];
    return AppStrings.invalidCode;
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
              Text(AppStrings.verifyCode, style: AppTextStyles.display),
              const SizedBox(height: 12),
              Text.rich(
                TextSpan(
                  style: AppTextStyles.bodySecondary,
                  children: [
                    const TextSpan(text: '${AppStrings.codeSentTo} '),
                    TextSpan(
                      text: widget.email,
                      style: AppTextStyles.body,
                    ),
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
