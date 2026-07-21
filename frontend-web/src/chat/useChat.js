import { useEffect, useState, useSyncExternalStore } from 'react';
import { ChatController } from './ChatController';

// Instantiates a ChatController for the given room and binds its state to React.
// opts must be stable for the life of the screen (derived from the route).
export function useChat(opts) {
  const [ctrl] = useState(() => new ChatController(opts));
  const state = useSyncExternalStore(ctrl.subscribe, ctrl.getState, ctrl.getState);
  useEffect(() => {
    ctrl.start();
    return () => ctrl.dispose();
  }, [ctrl]);
  return [state, ctrl];
}
