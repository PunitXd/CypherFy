import { useState } from 'react';
import { useNavigate, Link } from 'react-router-dom';
import { authApi } from '../api/auth';
import { errMsg } from '../api/client';
import { useAuth } from '../store/auth';
import PasswordInput from '../components/PasswordInput';
import GoogleButton from '../components/GoogleButton';
import Notice from '../components/Notice';

export default function Login() {
  const nav = useNavigate();
  const setUser = useAuth((s) => s.setUser);
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(false);

  async function submit(e) {
    e.preventDefault();
    setError('');
    setLoading(true);
    try {
      const { user } = await authApi.login({ email, password });
      setUser(user);
      nav('/app');
    } catch (err) {
      const status = err?.response?.status;
      const data = err?.response?.data?.data;
      // Unverified account → backend re-sent a code and asks us to verify.
      if (status === 403 && data?.verificationRequired) {
        nav('/verify', { state: { email: data.email || email } });
        return;
      }
      setError(errMsg(err, 'Invalid credentials'));
    } finally {
      setLoading(false);
    }
  }

  return (
    <form onSubmit={submit} className="auth-form">
      <h2 className="login-title">Welcome Back</h2>
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
        <PasswordInput
          placeholder="Password"
          value={password}
          onChange={setPassword}
          autoComplete="current-password"
        />
        <div className="forgot-password">
          <Link to="/forgot">Forgot Password?</Link>
        </div>
      </div>
      <button className="login-button" disabled={loading}>
        {loading ? 'Signing in…' : 'Sign In'}
      </button>
      <div className="divider">
        <span>or</span>
      </div>
      <GoogleButton onError={setError} />
      <div className="auth-footer">
        New here? <Link to="/register">Create account</Link>
      </div>
    </form>
  );
}
