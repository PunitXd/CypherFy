/// All user-facing copy lives here — no inline strings in widgets.
class AppStrings {
  AppStrings._();

  static const appName = 'CypherFy';
  static const tagline = 'End-to-end encrypted. Nothing kept.';

  // Home
  static const newRoom = 'New room';
  static const joinRoom = 'Join room';
  static const newRoomSub = 'Start an ephemeral encrypted room';
  static const joinRoomSub = 'Enter a 6-character code';
  static const yourChats = 'Your chats';
  static const noChats = 'No conversations yet';

  // Auth
  static const login = 'Log in';
  static const register = 'Create account';
  static const logout = 'Log out';
  static const email = 'Email';
  static const password = 'Password';
  static const displayName = 'Display name';
  static const username = 'Username';
  static const forgotPassword = 'Forgot password?';
  static const resetPassword = 'Reset password';
  // Password reset (OTP + link) flow
  static const forgotPasswordSub =
      "Enter your email and we'll send a 6-digit code (and a reset link).";
  static const sendCode = 'Send code';
  static const verifyCode = 'Enter verification code';
  static const codeSentTo = 'Enter the 6-digit code sent to';
  static const verify = 'Verify';
  static const resendCode = 'Resend code';
  static const codeResent = 'A new code has been sent.';
  static const invalidCode = 'Invalid or expired code';
  static const setNewPassword = 'Set a new password';
  static const newPassword = 'New password';
  static const confirmPassword = 'Confirm password';
  static const passwordsDontMatch = 'Passwords do not match';
  static const passwordResetDone = 'Password reset — please log in';
  static const changePassword = 'Change password';
  static const currentPassword = 'Current password';
  static const passwordChanged = 'Password changed';
  static const haveAccount = 'Already have an account? Log in';

  // Settings
  static const settings = 'Settings';
  static const account = 'Account';
  static const appearance = 'Appearance';
  static const darkMode = 'Dark mode';
  static const darkModeSub = 'Use the dark theme';
  static const about = 'About';
  static const version = 'Version';
  static const licenses = 'Open-source licenses';
  static const howEncryptionWorks = 'How encryption works';
  static const dangerZone = 'Danger zone';
  // ── Notifications ──
  static const notifications = 'Notifications';
  static const pushNotifications = 'Push notifications';
  static const pushNotificationsSub = 'Alert this device when something arrives';
  static const receiveCalls = 'Receive calls';
  static const receiveCallsSub = 'Ring for incoming voice & video calls';
  // ── Privacy ──
  static const privacy = 'Privacy';
  static const showOnlineStatus = 'Show online status';
  static const showOnlineStatusSub = 'Let friends see when you\'re online';
  static const showLastSeen = 'Show last seen';
  static const showLastSeenSub = 'Let friends see when you were last active';
  // ── Delete account ──
  static const deleteAccount = 'Delete account';
  static const deleteAccountSub = 'Permanently erase your account and data';
  static const deleteAccountWarning =
      'This permanently deletes your account, your direct-message conversations, '
      'and all their messages. This cannot be undone.';
  static const deleteAccountConfirmHint = 'Type DELETE to confirm';
  static const deleteAccountCta = 'Delete my account';
  static const accountDeleted = 'Your account has been deleted';
  static const continueWithGoogle = 'Continue with Google';
  static const orDivider = 'or';
  static const noAccount = "Don't have an account? Sign up";
  static const continueAsGuest = 'Continue as guest';

  // Create room
  static const roomName = 'Room name';
  static const maxUsers = 'Max participants';
  static const roomLifetime = 'Room lifetime';
  static const lockRoom = 'Lock room (require knock)';
  static const createRoom = 'Create room';
  static const shareCode = 'Share this code';
  static const copyLink = 'Copy link';
  static const showQr = 'Show QR';

  // Join room
  static const enterCode = 'Enter room code';
  static const joining = 'Joining…';

  // Chat
  static const messageHint = 'Message';
  static const endRoom = 'End room';
  static const endRoomConfirm =
      'End this room for everyone? All messages and files are permanently deleted.';
  static const roomEnded = 'This room has ended';
  static const roomExpired = 'This room has expired';
  static const roomExpiringSoon = 'Room expires in 60 seconds';
  static const newMessage = 'New message';

  // Profile
  static const profile = 'Profile';
  static const editProfile = 'Edit profile';
  static const contacts = 'Friends';
  static const friends = 'Friends';
  static const chatRequests = 'Requests';
  static const deleteConversation = 'Delete conversation';
  static const deleteConversationConfirm =
      'Delete this conversation on your side? The other person keeps their copy.';
  static const sendChatRequest = 'Send chat request';
  static const accept = 'Accept';
  static const reject = 'Reject';
  static const bio = 'Bio';

  // Common
  static const cancel = 'Cancel';
  static const confirm = 'Confirm';
  static const save = 'Save';
  static const retry = 'Retry';
  static const somethingWrong = 'Something went wrong';
}
