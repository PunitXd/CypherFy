import { useNavigate } from 'react-router-dom';
import { ArrowLeft } from 'lucide-react';

// Simple back-header layout shared by the authed sub-screens.
export default function Page({ title, action, children }) {
  const nav = useNavigate();
  return (
    <div className="page">
      <header className="page-header">
        <button className="icon-btn" onClick={() => nav(-1)} title="Back">
          <ArrowLeft size={18} />
        </button>
        <h1>{title}</h1>
        <div className="page-action">{action}</div>
      </header>
      <div className="page-body">{children}</div>
    </div>
  );
}
