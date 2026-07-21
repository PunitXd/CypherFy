import Page from '../components/Page';

const FACTS = [
  ['Cipher', 'AES-256-GCM'],
  ['Key derivation', 'PBKDF2 · SHA-256'],
  ['Iterations', '100,000'],
  ['Ephemeral room key', 'from the room code'],
  ['Direct-message key', 'from the room id'],
  ['Calls', 'DTLS-SRTP (peer-to-peer)'],
  ['Server sees', 'ciphertext only'],
];

const INVARIANTS = [
  'No plaintext is ever stored in the database.',
  'No raw encryption key ever reaches the server.',
  'Call media flows peer-to-peer; the server only relays signalling.',
  'Push notifications never include message content.',
];

export default function EncryptionInfo() {
  return (
    <Page title="How encryption works">
      <div className="settings-card">
        <p className="muted">
          Every message, file and file name is encrypted on your device before it leaves.
          The server only ever relays ciphertext — it cannot read your conversations.
        </p>
      </div>

      <div className="settings-card">
        <h3>The details</h3>
        <div className="cx-card details-table">
          {FACTS.map(([k, v], i) => (
            <div className="details-row" key={k} style={{ borderBottom: i < FACTS.length - 1 ? '1px solid var(--divider)' : 'none' }}>
              <span className="cx-muted">{k}</span>
              <span className="mono" style={{ fontSize: 11.5, color: 'var(--t1)', textAlign: 'right' }}>{v}</span>
            </div>
          ))}
        </div>
      </div>

      <div className="settings-card">
        <h3>Security invariants</h3>
        <ul className="enc-list">
          {INVARIANTS.map((x) => <li key={x}>{x}</li>)}
        </ul>
      </div>
    </Page>
  );
}
