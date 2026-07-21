import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../presentation/providers/chat_provider.dart';

import '../../presentation/screens/splash_screen.dart';
import '../../presentation/screens/home_screen.dart';
import '../../presentation/screens/main_shell.dart';
import '../../presentation/screens/search_screen.dart';
import '../../presentation/screens/auth/login_screen.dart';
import '../../presentation/screens/auth/register_screen.dart';
import '../../presentation/screens/auth/forgot_password_screen.dart';
import '../../presentation/screens/auth/verify_otp_screen.dart';
import '../../presentation/screens/auth/verify_email_screen.dart';
import '../../presentation/screens/auth/reset_password_screen.dart';
import '../../presentation/screens/room/create_room_screen.dart';
import '../../presentation/screens/room/join_room_screen.dart';
import '../../presentation/screens/room/chat_screen.dart';
import '../../presentation/screens/room/room_detail_screen.dart';
import '../../presentation/screens/profile/profile_screen.dart';
import '../../presentation/screens/profile/contacts_screen.dart';
import '../../presentation/screens/profile/edit_profile_screen.dart';
import '../../presentation/screens/settings/settings_screen.dart';
import '../../presentation/screens/settings/change_password_screen.dart';
import '../../presentation/screens/settings/delete_account_screen.dart';
import '../../presentation/screens/settings/encryption_info_screen.dart';

/// Named route paths, referenced throughout the app.
class Routes {
  Routes._();
  static const splash = '/';
  static const home = '/home'; // Home tab (shell branch 0)
  static const search = '/search'; // Search tab (shell branch 1)
  static const me = '/me'; // own Profile tab (shell branch 2)
  static const login = '/login';
  static const register = '/register';
  static const forgotPassword = '/forgot-password';
  static const verifyOtp = '/verify-otp'; // extra: String email
  static const verifyEmail = '/verify-email'; // extra: EmailVerifyArgs
  static const resetPassword = '/reset-password'; // extra: {email, token} OR query
  static const createRoom = '/room/create';
  static const joinRoom = '/room/join';
  static const chat = '/room/chat'; // extra: ChatArgs
  static const roomDetail = '/room/detail'; // extra: RoomDetailArgs (ephemeral)
  static const profile = '/profile'; // other user (query: userId)
  static const editProfile = '/edit-profile';
  static const contacts = '/contacts';
  static const settings = '/settings';
  static const changePassword = '/change-password';
  static const deleteAccount = '/delete-account';
  static const encryptionInfo = '/encryption-info';
}

/// Arguments passed to the chat screen (works for both room types).
class ChatArgs {
  final bool isEphemeral;
  final String? code; // ephemeral: the room key is DERIVED from this code
  final String? roomId; // permanent
  final String? title;
  final bool isHost;
  final DateTime? expiresAt; // ephemeral: drives the TTL countdown
  final String? alias; // the identity used to join (host uses its createdBy alias)
  final bool isLocked; // ephemeral: locked rooms require a knock to enter
  final String? otherUserId; // permanent: the DM partner (for the profile tap)
  final String? avatarUrl; // permanent: the DM partner's avatar for the app bar

  const ChatArgs({
    required this.isEphemeral,
    this.code,
    this.roomId,
    this.title,
    this.isHost = false,
    this.expiresAt,
    this.alias,
    this.isLocked = false,
    this.otherUserId,
    this.avatarUrl,
  });
}

/// Arguments for the email-verification screen (registration OTP step). The
/// password rides along so we can derive the in-memory wrapping key once the
/// code is confirmed — exactly as login does.
class EmailVerifyArgs {
  final String email;
  final String password;
  const EmailVerifyArgs({required this.email, required this.password});
}

/// Arguments for the ephemeral Room Detail page. Carries the static room data
/// plus the *live* chat provider instance (created locally in the chat screen)
/// so the detail page can watch the roster/count as it changes. The chat screen
/// stays mounted beneath the pushed detail route, keeping the provider alive.
class RoomDetailArgs {
  final ChatArgs chat;
  final String? myAlias;
  final StateNotifierProvider<ChatNotifier, ChatState> provider;
  const RoomDetailArgs({
    required this.chat,
    required this.provider,
    this.myAlias,
  });
}

/// Observes route transitions so screens (e.g. Home) can refresh when they are
/// returned to after a pushed route pops.
final RouteObserver<ModalRoute<void>> routeObserver =
    RouteObserver<ModalRoute<void>>();

/// False on a fresh Dart start (first load / web refresh), flipped true once the
/// Splash screen has run. Used by the router redirect to detect a cold load.
bool routerBooted = false;

/// Central go_router configuration.
GoRouter buildRouter() {
  return GoRouter(
    initialLocation: Routes.splash,
    observers: [routeObserver],
    redirect: (context, state) {
      // On a cold load (first paint / web refresh) all in-memory route state is
      // gone — including a room's ChatArgs, which travel via go_router `extra`.
      // The browser URL after an imperative push isn't reliably the room route
      // either, so we can't tell "was in a room" from the location alone. Route
      // EVERY cold load through Splash, which restores the session and drops the
      // user back into their active room (or Home). routerBooted is false only
      // on a fresh Dart start; in-app navigation (true) is never redirected.
      //
      // Exception: the emailed password-reset link carries its token in the URL
      // and must be allowed to load directly.
      final loc = state.matchedLocation;
      if (!routerBooted &&
          loc != Routes.splash &&
          loc != Routes.resetPassword) {
        return Routes.splash;
      }
      return null;
    },
    routes: [
      GoRoute(
        path: Routes.splash,
        builder: (_, __) => const SplashScreen(),
      ),
      // Tab shell: Home / Search / Profile. The bottom bar (in MainShell) only
      // shows when logged in, so a guest just sees the standalone Home.
      StatefulShellRoute.indexedStack(
        builder: (_, __, shell) => MainShell(navigationShell: shell),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(
              path: Routes.home,
              builder: (_, __) => const HomeScreen(),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: Routes.search,
              builder: (_, __) => const SearchScreen(),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: Routes.me,
              builder: (_, __) => const ProfileScreen(),
            ),
          ]),
        ],
      ),
      GoRoute(
        path: Routes.login,
        builder: (_, __) => const LoginScreen(),
      ),
      GoRoute(
        path: Routes.register,
        builder: (_, __) => const RegisterScreen(),
      ),
      GoRoute(
        path: Routes.forgotPassword,
        builder: (_, state) =>
            ForgotPasswordScreen(initialEmail: state.extra as String?),
      ),
      GoRoute(
        path: Routes.verifyOtp,
        builder: (_, state) =>
            VerifyOtpScreen(email: state.extra as String? ?? ''),
      ),
      GoRoute(
        path: Routes.verifyEmail,
        builder: (_, state) {
          final args = state.extra as EmailVerifyArgs?;
          if (args == null) return const LoginScreen();
          return VerifyEmailScreen(email: args.email, password: args.password);
        },
      ),
      GoRoute(
        path: Routes.resetPassword,
        builder: (_, state) {
          // In-app (OTP path) passes {email, token} via extra; the emailed web
          // link arrives with ?token=&email= query params instead.
          final extra = state.extra as Map<String, dynamic>?;
          final q = state.uri.queryParameters;
          return ResetPasswordScreen(
            email: (extra?['email'] ?? q['email'] ?? '') as String,
            token: (extra?['token'] ?? q['token'] ?? '') as String,
          );
        },
      ),
      GoRoute(
        path: Routes.createRoom,
        builder: (_, __) => const CreateRoomScreen(),
      ),
      GoRoute(
        path: Routes.joinRoom,
        builder: (_, __) => const JoinRoomScreen(),
      ),
      GoRoute(
        path: Routes.chat,
        builder: (context, state) {
          // extra is null only on a stray cold load; Splash restores the real
          // room, so fall back to it rather than crashing on a null cast.
          final args = state.extra as ChatArgs?;
          if (args == null) return const SplashScreen();
          return ChatScreen(args: args);
        },
      ),
      GoRoute(
        path: Routes.roomDetail,
        builder: (context, state) {
          final args = state.extra as RoomDetailArgs?;
          if (args == null) return const SplashScreen();
          return RoomDetailScreen(args: args);
        },
      ),
      GoRoute(
        path: Routes.profile,
        builder: (context, state) {
          // Optional userId query for viewing another user's profile.
          final userId = state.uri.queryParameters['userId'];
          return ProfileScreen(userId: userId);
        },
      ),
      GoRoute(
        path: Routes.editProfile,
        builder: (_, __) => const EditProfileScreen(),
      ),
      GoRoute(
        path: Routes.contacts,
        // extra: an int initial tab index (2 = Requests, e.g. from a push tap).
        builder: (_, state) =>
            ContactsScreen(initialTab: state.extra is int ? state.extra as int : 0),
      ),
      GoRoute(
        path: Routes.settings,
        builder: (_, __) => const SettingsScreen(),
      ),
      GoRoute(
        path: Routes.changePassword,
        builder: (_, __) => const ChangePasswordScreen(),
      ),
      GoRoute(
        path: Routes.deleteAccount,
        builder: (_, __) => const DeleteAccountScreen(),
      ),
      GoRoute(
        path: Routes.encryptionInfo,
        builder: (_, __) => const EncryptionInfoScreen(),
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      body: Center(child: Text('Route not found: ${state.uri}')),
    ),
  );
}
