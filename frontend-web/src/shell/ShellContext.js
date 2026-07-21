import { createContext, useContext } from 'react';

// Shared state for the 3-column shell: the details-panel toggle and the active
// conversation's metadata (set by ChatPane, read by the header + DetailsPanel).
export const ShellContext = createContext(null);
export const useShell = () => useContext(ShellContext);
