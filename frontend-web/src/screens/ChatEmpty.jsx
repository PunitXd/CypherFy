import { Lock } from 'lucide-react';

// Shown in the main pane when no conversation is open.
export default function ChatEmpty() {
  return (
    <div className="chat-empty">
      <div className="chat-empty-logo"><Lock size={22} /></div>
      <h2>CypherFy</h2>
      <p className="cx-muted">Select a conversation, or start a new one with ＋.</p>
      <p className="cx-dim mono" style={{ fontSize: 11, marginTop: 4 }}>end-to-end encrypted · AES-256-GCM</p>
    </div>
  );
}
