import { useState } from 'react';
import { useNavigate, Link } from 'react-router-dom';
import { authApi } from '../api/auth';
import { errMsg } from '../api/client';
import PasswordInput from '../components/PasswordInput';
import GoogleButton from '../components/GoogleButton';
import Notice from '../components/Notice';

export default function Register() {
  const nav = useNavigate();
  const [form, setForm] = useState({
    email: '',
    displayName: '',
    username: '',
    password: '',
    confirm: '',
  });
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(false);

  const set = (k) => (v) => setForm((f) => ({ ...f, [k]: v }));

  function validate() {
    if (!form.email || !form.displayName || !form.username || !form.password) {
      return 'All fields are required';
    }
    if (!/^[a-zA-Z0-9_]{3,20}$/.test(form.username)) {
      return 'Username must be 3–20 letters, numbers or underscores';
    }
    if (form.password.length < 8) return 'Password must be at least 8 characters';
    if (form.password !== form.confirm) return 'Passwords do not match';
    return '';
  }

  async function submit(e) {
    e.preventDefault();
    const v = validate();
    if (v) {
      setError(v);
      return;
    }
    setError('');
    setLoading(true);
    try {
      await authApi.register({
        email: form.email,
        password: form.password,
        displayName: form.displayName,
        username: form.username,
      });
      // Backend emailed an OTP; move to verification.
      nav('/verify', { state: { email: form.email } });
    } catch (err) {
      setError(errMsg(err, 'Could not create account'));
    } finally {
      setLoading(false);
    }
  }

  return (
    <form onSubmit={submit} className="auth-form">
      <h2 className="login-title">Create account</h2>
      <Notice type="error">{error}</Notice>
      <div className="login-input-group">
        <input
          type="email"
          placeholder="Email address"
          className="login-input"
          value={form.email}
          onChange={(e) => set('email')(e.target.value)}
          autoComplete="email"
          required
        />
        <input
          type="text"
          placeholder="Display name"
          className="login-input"
          value={form.displayName}
          onChange={(e) => set('displayName')(e.target.value)}
          autoComplete="name"
          required
        />
        <input
          type="text"
          placeholder="Username"
          className="login-input"
          value={form.username}
          onChange={(e) => set('username')(e.target.value)}
          autoComplete="username"
          required
        />
        <PasswordInput
          placeholder="Password"
          value={form.password}
          onChange={set('password')}
        />
        <PasswordInput
          placeholder="Confirm password"
          value={form.confirm}
          onChange={set('confirm')}
        />
      </div>
      <button className="login-button" disabled={loading}>
        {loading ? 'Creating…' : 'Create account'}
      </button>
      <div className="divider">
        <span>or</span>
      </div>
      <GoogleButton onError={setError} />
      <div className="auth-footer">
        Have an account? <Link to="/">Sign in</Link>
      </div>
    </form>
  );
}
