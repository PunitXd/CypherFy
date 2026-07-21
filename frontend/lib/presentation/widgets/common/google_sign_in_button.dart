import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../../core/constants/app_strings.dart';
import '../../../core/router/app_router.dart';
import '../../../services/firebase_auth_service.dart';
import '../../providers/auth_provider.dart';
import '../../providers/room_provider.dart';
import 'app_button.dart';

/// "Continue with Google" — signs in through Firebase Auth on every platform
/// (web popup + mobile native picker), exchanges the Firebase ID token for our
/// session, and lands the user home.
class GoogleSignInButton extends ConsumerStatefulWidget {
  const GoogleSignInButton({super.key});

  @override
  ConsumerState<GoogleSignInButton> createState() => _GoogleSignInButtonState();
}

class _GoogleSignInButtonState extends ConsumerState<GoogleSignInButton> {
  bool _busy = false;

  Future<void> _signIn() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final idToken = await FirebaseAuthService.instance.signInWithGoogle();
      if (idToken == null) {
        if (mounted) setState(() => _busy = false);
        return;
      }
      final ok =
          await ref.read(authProvider.notifier).signInWithFirebase(idToken);
      if (!mounted) return;
      setState(() => _busy = false);
      if (ok) {
        await ref.read(roomProvider.notifier).loadPermanent();
        if (mounted) context.go(Routes.home);
      } else {
        _snack(ref.read(authProvider).error ?? 'Google sign-in failed');
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) setState(() => _busy = false);
      // User dismissed the popup — not an error worth surfacing.
      const cancels = {
        'popup-closed-by-user',
        'cancelled-popup-request',
        'web-context-canceled',
        'user-cancelled',
      };
      if (!cancels.contains(e.code)) _snack('Google sign-in failed');
    } on GoogleSignInException catch (e) {
      if (mounted) setState(() => _busy = false);
      if (e.code != GoogleSignInExceptionCode.canceled) {
        _snack('Google sign-in failed');
      }
    } catch (_) {
      if (mounted) setState(() => _busy = false);
      _snack('Google sign-in failed');
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return AppButton(
      label: AppStrings.continueWithGoogle,
      secondary: true,
      icon: Icons.g_mobiledata,
      loading: _busy,
      onPressed: _signIn,
    );
  }
}
