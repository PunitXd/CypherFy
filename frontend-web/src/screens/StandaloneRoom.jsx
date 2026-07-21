import ChatPane from './ChatPane';

// Full-screen ephemeral room for guests opening a shared /room/:code link
// (no sidebar/shell). Owns its own socket (standalone) and closes it on leave.
export default function StandaloneRoom() {
  return (
    <div className="cipher" style={{ height: '100vh', display: 'flex' }}>
      <div className="shell-main" style={{ width: '100%', height: '100%' }}>
        <ChatPane ephemeral standalone />
      </div>
    </div>
  );
}
