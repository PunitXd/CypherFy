import { useState, useRef } from 'react';
import { useNavigate } from 'react-router-dom';
import { LogOut, Camera } from 'lucide-react';
import { userApi } from '../api/users';
import { authApi } from '../api/auth';
import { errMsg } from '../api/client';
import { useAuth } from '../store/auth';
import { enableWebPush, pushConfigured } from '../push/webpush';
import { useTheme } from '../store/theme';
import Page from '../components/Page';
import Avatar from '../components/Avatar';
import PasswordInput from '../components/PasswordInput';
import Notice from '../components/Notice';

export default function Settings() {
  const nav = useNavigate();
  const user = useAuth((s) => s.user);
  const updateUser = useAuth((s) => s.updateUser);
  const logout = useAuth((s) => s.logout);
  const { theme, toggle: toggleTheme } = useTheme();

  const [displayName, setDisplayName] = useState(user?.displayName || '');
  const [bio, setBio] = useState(user?.bio || '');
  const [username, setUsername] = useState(user?.username || '');
  const [msg, setMsg] = useState('');
  const [error, setError] = useState('');
  const [savingProfile, setSavingProfile] = useState(false);

  // Change password
  const [curPw, setCurPw] = useState('');
  const [newPw, setNewPw] = useState('');
  const [pwMsg, setPwMsg] = useState('');
  const [pwErr, setPwErr] = useState('');

  // Delete account
  const [delPw, setDelPw] = useState('');
  const [delErr, setDelErr] = useState('');
  const [confirmDelete, setConfirmDelete] = useState(false);

  const [pushMsg, setPushMsg] = useState('');

  // Avatar upload
  const avatarRef = useRef(null);
  const [avatarErr, setAvatarErr] = useState('');
  const [avatarBusy, setAvatarBusy] = useState(false);

  async function onPickAvatar(e) {
    const file = e.target.files?.[0];
    e.target.value = '';
    if (!file) return;
    setAvatarErr('');
    if (!file.type.startsWith('image/')) { setAvatarErr('Please choose an image file'); return; }
    if (file.size > 5 * 1024 * 1024) { setAvatarErr('Image must be under 5 MB'); return; }
    setAvatarBusy(true);
    try {
      const { avatar } = await userApi.uploadAvatar(file);
      updateUser({ avatar });
    } catch (err) {
      setAvatarErr(errMsg(err, 'Could not upload photo'));
    } finally {
      setAvatarBusy(false);
    }
  }

  async function saveProfile(e) {
    e.preventDefault();
    setError('');
    setMsg('');
    setSavingProfile(true);
    try {
      const patch = { displayName, bio };
      if (username !== user.username) patch.username = username;
      const updated = await userApi.updateMe(patch);
      updateUser(updated);
      setMsg('Profile saved');
    } catch (err) {
      setError(errMsg(err, 'Could not save profile'));
    } finally {
      setSavingProfile(false);
    }
  }

  async function togglePref(key, value) {
    setError('');
    try {
      const updated = await userApi.updateMe({ [key]: value });
      updateUser(updated);
    } catch (err) {
      setError(errMsg(err, 'Could not update setting'));
    }
  }

  async function changePassword(e) {
    e.preventDefault();
    setPwErr('');
    setPwMsg('');
    if (newPw.length < 8) {
      setPwErr('New password must be at least 8 characters');
      return;
    }
    try {
      await authApi.changePassword({ currentPassword: curPw, newPassword: newPw });
      setPwMsg('Password changed');
      setCurPw('');
      setNewPw('');
    } catch (err) {
      setPwErr(errMsg(err, 'Could not change password'));
    }
  }

  async function enablePush() {
    setPushMsg('');
    const res = await enableWebPush();
    setPushMsg(res.ok ? res.note || 'Notifications enabled' : res.reason);
  }

  async function deleteAccount(e) {
    e.preventDefault();
    setDelErr('');
    try {
      await userApi.deleteAccount(delPw);
      await logout();
      nav('/');
    } catch (err) {
      setDelErr(errMsg(err, 'Could not delete account'));
    }
  }

  return (
    <Page
      title="Settings"
      action={
        <button className="logout-btn" onClick={async () => { await logout(); nav('/'); }}>
          <LogOut size={14} /> Log out
        </button>
      }
    >
      <div className="settings-head">
        <button className="avatar-edit" onClick={() => avatarRef.current?.click()} title="Change photo" disabled={avatarBusy}>
          <Avatar src={user?.avatar} name={user?.displayName} size={76} />
          <span className="avatar-edit-badge">{avatarBusy ? '…' : <Camera size={13} />}</span>
        </button>
        <input ref={avatarRef} type="file" accept="image/*" hidden onChange={onPickAvatar} />
      </div>
      <Notice type="error">{avatarErr}</Notice>

      {/* Profile */}
      <form className="settings-card" onSubmit={saveProfile}>
        <h3>Profile</h3>
        <Notice type="error">{error}</Notice>
        <Notice type="success">{msg}</Notice>
        <label className="field">Display name
          <input className="login-input" value={displayName} onChange={(e) => setDisplayName(e.target.value)} />
        </label>
        <label className="field">Username
          <input className="login-input" value={username} onChange={(e) => setUsername(e.target.value.toLowerCase())} />
          <span className="hint">Changeable once every 30 days · 3–20 letters, numbers, underscores</span>
        </label>
        <label className="field">Bio
          <textarea className="login-input" rows={3} value={bio} onChange={(e) => setBio(e.target.value)} />
        </label>
        <button className="login-button" disabled={savingProfile}>{savingProfile ? 'Saving…' : 'Save profile'}</button>
      </form>

      {/* Privacy */}
      <div className="settings-card">
        <h3>Privacy & calls</h3>
        <Toggle label="Show online status" checked={user?.showOnlineStatus !== false} onChange={(v) => togglePref('showOnlineStatus', v)} />
        <Toggle label="Show last seen" checked={user?.showLastSeen !== false} onChange={(v) => togglePref('showLastSeen', v)} />
        <Toggle label="Allow calls" checked={user?.receiveCalls !== false} onChange={(v) => togglePref('receiveCalls', v)} />
      </div>

      {/* Notifications */}
      <div className="settings-card">
        <h3>Notifications</h3>
        <p className="muted">Content-free push for messages, calls and requests.</p>
        <button className="login-button ghost" onClick={enablePush} disabled={!pushConfigured()}>
          {pushConfigured() ? 'Enable notifications' : 'Push not configured'}
        </button>
        {pushMsg && <p className="hint">{pushMsg}</p>}
      </div>

      {/* Appearance */}
      <div className="settings-card">
        <h3>Appearance</h3>
        <Toggle label="Light theme" checked={theme === 'light'} onChange={() => toggleTheme()} />
      </div>

      {/* About */}
      <div className="settings-card">
        <h3>About</h3>
        <button className="settings-link" onClick={() => nav('/settings/encryption')}>
          How encryption works <span className="cx-dim">›</span>
        </button>
        <div className="toggle-row">
          <span className="cx-muted">Version</span>
          <span className="mono cx-dim">CypherFy Web · 0.1.0</span>
        </div>
      </div>

      {/* Security */}
      <form className="settings-card" onSubmit={changePassword}>
        <h3>Change password</h3>
        <Notice type="error">{pwErr}</Notice>
        <Notice type="success">{pwMsg}</Notice>
        <PasswordInput placeholder="Current password" value={curPw} onChange={setCurPw} autoComplete="current-password" />
        <PasswordInput placeholder="New password" value={newPw} onChange={setNewPw} />
        <button className="login-button">Change password</button>
        <button type="button" className="settings-link" onClick={() => nav('/forgot')}>
          Forgot your password? Reset via email <span className="cx-dim">›</span>
        </button>
      </form>

      {/* Danger zone */}
      <div className="settings-card danger-zone">
        <h3>Delete account</h3>
        <p className="muted">Permanently deletes your account, DMs and messages. This cannot be undone.</p>
        {!confirmDelete ? (
          <button className="login-button danger" onClick={() => setConfirmDelete(true)}>Delete account</button>
        ) : (
          <form onSubmit={deleteAccount}>
            <Notice type="error">{delErr}</Notice>
            <PasswordInput placeholder="Confirm your password" value={delPw} onChange={setDelPw} autoComplete="current-password" />
            <div className="row">
              <button type="button" className="login-button ghost" onClick={() => setConfirmDelete(false)}>Cancel</button>
              <button type="submit" className="login-button danger">Permanently delete</button>
            </div>
          </form>
        )}
      </div>
    </Page>
  );
}

function Toggle({ label, checked, onChange }) {
  return (
    <label className="toggle-row">
      <span>{label}</span>
      <input type="checkbox" checked={checked} onChange={(e) => onChange(e.target.checked)} />
    </label>
  );
}
