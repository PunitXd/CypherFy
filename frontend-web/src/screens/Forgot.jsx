import { useState } from 'react';
import { useNavigate, Link } from 'react-router-dom';
import { authApi } from '../api/auth';
import { errMsg } from '../api/client';
import Notice from '../components/Notice';

export default function Forgot() {
  const nav = useNavigate();
  const [email, setEmail] = useState('');
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(false);

  async function submit(e) {
    e.preventDefault();
    setError('');
    setLoading(true);
    try {
      await authApi.forgotPassword(email);
      // Always generic — never reveals whether the email exists.
      nav('/reset', { state: { email, sent: true } });
    } catch (err) {
      setError(errMsg(err, 'Could not send the reset code'));
    } finally {
      setLoading(false);
    }
  }

  return (
    <form onSubmit={submit} className="auth-form">
      <h2 className="login-title">Reset password</h2>
      <p className="auth-subtitle">
        Enter your email and we&apos;ll send a code to reset your password.
      </p>
      <Notice type="error">{error}</Notice>
      <div className="login-input-group">
        <input
          type="email"
          placeholder="Email address"
          className="login-input"
          value={email}
          onChange={(e) => setEmail(e.target.value)}
          autoComplete="email"
          required
        />
      </div>
      <button className="login-button" disabled={loading}>
        {loading ? 'Sending…' : 'Send reset code'}
      </button>
      <div className="auth-footer">
        <Link to="/">Back to sign in</Link>
      </div>
    </form>
  );
}
