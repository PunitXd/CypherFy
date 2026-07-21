import { useEffect, useRef, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { userApi } from '../api/users';
import { errMsg } from '../api/client';
import Page from '../components/Page';
import Avatar from '../components/Avatar';
import Notice from '../components/Notice';

export default function Search() {
  const nav = useNavigate();
  const [q, setQ] = useState('');
  const [results, setResults] = useState([]);
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(false);
  const debounce = useRef(null);

  useEffect(() => {
    clearTimeout(debounce.current);
    const query = q.trim();
    if (!query) {
      setResults([]);
      return;
    }
    debounce.current = setTimeout(async () => {
      setLoading(true);
      setError('');
      try {
        setResults(await userApi.search(query));
      } catch (e) {
        setError(errMsg(e, 'Search failed'));
      } finally {
        setLoading(false);
      }
    }, 300);
    return () => clearTimeout(debounce.current);
  }, [q]);

  return (
    <Page title="Find people">
      <input
        className="login-input"
        placeholder="Search by @username"
        value={q}
        onChange={(e) => setQ(e.target.value)}
        autoFocus
      />
      <Notice type="error">{error}</Notice>
      {loading && <p className="muted">Searching…</p>}
      {!loading && q.trim() && results.length === 0 && (
        <p className="muted">No users found.</p>
      )}
      <ul className="user-list">
        {results.map((u) => (
          <li key={u._id}>
            <button onClick={() => nav(`/u/${u._id}`)}>
              <Avatar src={u.avatar} name={u.displayName} />
              <div className="user-line">
                <span className="user-name">{u.displayName}</span>
                <span className="muted">@{u.username}</span>
              </div>
              {u.isOnline && <span className="dot-online" title="Online" />}
            </button>
          </li>
        ))}
      </ul>
    </Page>
  );
}
