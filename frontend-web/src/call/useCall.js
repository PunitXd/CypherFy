import { useSyncExternalStore } from 'react';
import { callController } from './CallController';

// Subscribe to the global call state.
export function useCall() {
  return useSyncExternalStore(
    callController.subscribe,
    callController.getState,
    callController.getState
  );
}
