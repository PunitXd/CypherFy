import { useEffect, useRef, useState } from 'react';
import { useNavigate, useLocation, Link } from 'react-router-dom';
import { authApi } from '../api/auth';
import { errMsg } from '../api/client';
import { useAuth } from '../store/auth';
import Notice from '../components/Notice';

export default function Verify() {
  const nav = useNavigate();
  const loc = useLocation();
  const setUser = useAuth((s) => s.setUser);

  const [email, setEmail] = useState(loc.state?.email || '');
  const [otp, setOtp] = useState('');
  const [error, setError] = useState('');
  const [info, setInfo] = useState('');
  const [loading, setLoading] = useState(false);
  const [cooldown, setCooldown] = useState(0);
  const timer = useRef(null);

  useEffect(() => () => clearInterval(timer.current), []);

  function startCooldown() {
    setCooldown(30);
    clearInterval(timer.current);
    timer.current = setInterval(() => {
      setCooldown((c) => {
        if (c <= 1) clearInterval(timer.current);
        return c - 1;
      });
    }, 1000);
  }

  async function submit(e) {
    e.preventDefault();
    setError('');
    setLoading(true);
    try {
      const { user } = await authApi.verifyEmail({ email, otp });
      setUser(user);
      nav('/app');
    } catch (err) {
      setError(errMsg(err, 'Incorrect or expired code'));
    } finally {
      setLoading(false);
    }
  }

  async function resend() {
    if (cooldown > 0 || !email) return;
    setError('');
    setInfo('');
    try {
      await authApi.resendVerification(email);
      setInfo('A new code was sent to your email');
      startCooldown();
    } catch (err) {
      setError(errMsg(err, 'Could not resend the code'));
    }
  }

  return (
    <form onSubmit={submit} className="auth-form">
      <h2 className="login-title">Verify your email</h2>
      <p className="auth-subtitle">
        Enter the 6-digit code sent to {email || 'your email'}.
      </p>
      <Notice type="error">{error}</Notice>
      <Notice type="success">{info}</Notice>
      <div className="login-input-group">
        {!loc.state?.email && (
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
        {loading ? 'Verifying…' : 'Verify'}
      </button>
      <div className="auth-footer">
        <button type="button" className="link linkbtn" onClick={resend} disabled={cooldown > 0}>
          {cooldown > 0 ? `Resend code (${cooldown}s)` : 'Resend code'}
        </button>
        {' · '}
        <Link to="/">Back to sign in</Link>
      </div>
    </form>
  );
}
