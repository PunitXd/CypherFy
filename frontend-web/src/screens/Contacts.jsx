import { useEffect, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { userApi } from '../api/users';
import { errMsg } from '../api/client';
import Page from '../components/Page';
import Avatar from '../components/Avatar';
import Notice from '../components/Notice';

export default function Contacts() {
  const nav = useNavigate();
  const [contacts, setContacts] = useState([]);
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    userApi
      .contacts()
      .then(setContacts)
      .catch((e) => setError(errMsg(e, 'Could not load contacts')))
      .finally(() => setLoading(false));
  }, []);

  return (
    <Page title="Contacts">
      <Notice type="error">{error}</Notice>
      {loading && <div className="spinner" />}
      {!loading && contacts.length === 0 && <p className="muted">No contacts yet.</p>}
      <ul className="user-list">
        {contacts.map((u) => (
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
