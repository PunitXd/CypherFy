import { useEffect, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { userApi } from '../api/users';
import { errMsg } from '../api/client';
import Page from '../components/Page';
import Avatar from '../components/Avatar';
import Notice from '../components/Notice';

export default function Requests() {
  const nav = useNavigate();
  const [incoming, setIncoming] = useState([]);
  const [outgoing, setOutgoing] = useState([]);
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(true);

  async function load() {
    try {
      const { incoming: inc, outgoing: out } = await userApi.getRequests();
      setIncoming(inc);
      setOutgoing(out);
    } catch (e) {
      setError(errMsg(e, 'Could not load requests'));
    } finally {
      setLoading(false);
    }
  }
  useEffect(() => {
    load();
  }, []);

  async function accept(r) {
    setError('');
    try {
      const room = await userApi.acceptRequest(r._id);
      nav(`/app/dm/${room._id}`, { state: { roomName: r.from.displayName } });
    } catch (e) {
      setError(errMsg(e, 'Could not accept'));
    }
  }
  async function reject(r) {
    setError('');
    try {
      await userApi.rejectRequest(r._id);
      setIncoming((list) => list.filter((x) => x._id !== r._id));
    } catch (e) {
      setError(errMsg(e, 'Could not reject'));
    }
  }

  return (
    <Page title="Message requests">
      <Notice type="error">{error}</Notice>
      {loading && <div className="spinner" />}

      <h3 className="section-label">Incoming</h3>
      {incoming.length === 0 ? (
        <p className="muted">No incoming requests.</p>
      ) : (
        <ul className="user-list">
          {incoming.map((r) => (
            <li key={r._id}>
              <button onClick={() => nav(`/u/${r.from._id}`)}>
                <Avatar src={r.from.avatar} name={r.from.displayName} />
                <div className="user-line">
                  <span className="user-name">{r.from.displayName}</span>
                  <span className="muted">@{r.from.username}</span>
                </div>
              </button>
              <div className="req-actions">
                <button className="mini" onClick={() => accept(r)}>Accept</button>
                <button className="mini ghost" onClick={() => reject(r)}>Reject</button>
              </div>
            </li>
          ))}
        </ul>
      )}

      <h3 className="section-label">Sent</h3>
      {outgoing.length === 0 ? (
        <p className="muted">No sent requests.</p>
      ) : (
        <ul className="user-list">
          {outgoing.map((r) => (
            <li key={r._id}>
              <button onClick={() => nav(`/u/${r.to._id}`)}>
                <Avatar src={r.to.avatar} name={r.to.displayName} />
                <div className="user-line">
                  <span className="user-name">{r.to.displayName}</span>
                  <span className="muted">@{r.to.username}</span>
                </div>
              </button>
              <span className="muted">Pending</span>
            </li>
          ))}
        </ul>
      )}
    </Page>
  );
}
