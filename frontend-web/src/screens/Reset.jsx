import { useState } from 'react';
import { useNavigate, useLocation, useSearchParams, Link } from 'react-router-dom';
import { authApi } from '../api/auth';
import { errMsg } from '../api/client';
import { useAuth } from '../store/auth';
import PasswordInput from '../components/PasswordInput';
import Notice from '../components/Notice';

// Two flows converge here:
//   - In-app: forgot → this screen asks for the OTP, exchanges it for a ticket,
//     then sets the new password.
//   - Emailed link: /reset?token=...&email=... skips the OTP step (the link
//     token IS the reset token).
export default function Reset() {
  const nav = useNavigate();
  const loc = useLocation();
  const [params] = useSearchParams();
  const logout = useAuth((s) => s.logout);

  const linkToken = params.get('token') || '';
  const initialEmail = loc.state?.email || params.get('email') || '';

  const [email, setEmail] = useState(initialEmail);
  const [step, setStep] = useState(linkToken ? 'password' : 'otp');
  const [otp, setOtp] = useState('');
  const [ticket, setTicket] = useState(linkToken);
  const [password, setPassword] = useState('');
  const [confirm, setConfirm] = useState('');
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(false);

  async function submitOtp(e) {
    e.preventDefault();
    setError('');
    setLoading(true);
    try {
      const { ticket: t } = await authApi.verifyOtp({ email, otp });
      setTicket(t);
      setStep('password');
    } catch (err) {
      setError(errMsg(err, 'Invalid or expired code'));
    } finally {
      setLoading(false);
    }
  }

  async function submitPassword(e) {
    e.preventDefault();
    if (password.length < 8) {
      setError('Password must be at least 8 characters');
      return;
    }
    if (password !== confirm) {
      setError('Passwords do not match');
      return;
    }
    setError('');
    setLoading(true);
    try {
      await authApi.resetPassword({ email, token: ticket, newPassword: password });
      // A reset invalidates every session server-side — clear any local session
      // so a logged-in user lands cleanly on login with their new password.
      await logout();
      nav('/', { state: { reset: true } });
    } catch (err) {
      setError(errMsg(err, 'Could not reset password'));
    } finally {
      setLoading(false);
    }
  }

  if (step === 'otp') {
    return (
      <form onSubmit={submitOtp} className="auth-form">
        <h2 className="login-title">Enter reset code</h2>
        <p className="auth-subtitle">
          If {email || 'that email'} is registered, a 6-digit code was sent.
        </p>
        <Notice type="error">{error}</Notice>
        <div className="login-input-group">
          {!initialEmail && (
            <input
              type="email"
              placeholder="Email address"
              className="login-input"
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              autoComplete="email"
              required
            />
          )}
          <input
            type="text"
            inputMode="numeric"
            maxLength={6}
            placeholder="••••••"
            className="login-input otp-input"
            value={otp}
            onChange={(e) => setOtp(e.target.value.replace(/\D/g, ''))}
            required
          />
        </div>
        <button className="login-button" disabled={loading || otp.length < 6}>
          {loading ? 'Checking…' : 'Continue'}
        </button>
        <div className="auth-footer">
          <Link to="/">Back to sign in</Link>
        </div>
      </form>
    );
  }

  return (
    <form onSubmit={submitPassword} className="auth-form">
      <h2 className="login-title">Set a new password</h2>
      <Notice type="error">{error}</Notice>
      <div className="login-input-group">
        <PasswordInput placeholder="New password" value={password} onChange={setPassword} />
        <PasswordInput placeholder="Confirm new password" value={confirm} onChange={setConfirm} />
      </div>
      <button className="login-button" disabled={loading}>
        {loading ? 'Saving…' : 'Reset password'}
      </button>
      <div className="auth-footer">
        <Link to="/">Back to sign in</Link>
      </div>
    </form>
  );
}
