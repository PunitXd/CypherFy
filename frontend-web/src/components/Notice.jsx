// Inline error / success banner shown inside the auth card.
export default function Notice({ type = 'error', children }) {
  if (!children) return null;
  return <div className={`notice ${type}`}>{children}</div>;
}
