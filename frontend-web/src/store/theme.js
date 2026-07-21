import { create } from 'zustand';

const KEY = 'sc_theme';

function apply(theme) {
  document.documentElement.dataset.theme = theme;
}

const initial = localStorage.getItem(KEY) || 'dark';
apply(initial);

export const useTheme = create((set) => ({
  theme: initial,
  setTheme(theme) {
    localStorage.setItem(KEY, theme);
    apply(theme);
    set({ theme });
  },
  toggle() {
    set((s) => {
      const next = s.theme === 'dark' ? 'light' : 'dark';
      localStorage.setItem(KEY, next);
      apply(next);
      return { theme: next };
    });
  },
}));
