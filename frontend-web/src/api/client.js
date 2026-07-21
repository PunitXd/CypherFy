// Shared axios client — mirrors frontend/lib/data/repositories/api_client.dart.
//
//  - Injects `Authorization: Bearer <access>` on every request.
//  - Sends `X-Client-Platform: web` so the backend mints the short (7d) refresh
//    lifetime (safer on shared machines).
//  - On a 401 (non-auth route), rotates the refresh token once and replays.
//  - Tokens live in localStorage; this React app owns its own web session.

import axios from 'axios';
import { API_BASE_URL } from '../config';

const ACCESS = 'sc_access';
const REFRESH = 'sc_refresh';

export const tokenStore = {
  get access() {
    return localStorage.getItem(ACCESS);
  },
  get refresh() {
    return localStorage.getItem(REFRESH);
  },
  save(access, refresh) {
    if (access) localStorage.setItem(ACCESS, access);
    if (refresh) localStorage.setItem(REFRESH, refresh);
  },
  clear() {
    localStorage.removeItem(ACCESS);
    localStorage.removeItem(REFRESH);
  },
};

export const api = axios.create({
  baseURL: API_BASE_URL,
  timeout: 15000,
  headers: {
    'Content-Type': 'application/json',
    'X-Client-Platform': 'web',
  },
});

// Unwrap the standard { statusCode, data, message } envelope.
export const unwrap = (res) => res.data?.data;

// Human-friendly message from an axios error (backend sends { message }).
export const errMsg = (e, fallback = 'Something went wrong') =>
  e?.response?.data?.message || e?.message || fallback;

api.interceptors.request.use((cfg) => {
  const t = tokenStore.access;
  if (t) cfg.headers.Authorization = `Bearer ${t}`;
  return cfg;
});

// Single in-flight refresh shared across concurrent 401s.
let refreshing = null;

api.interceptors.response.use(
  (res) => res,
  async (error) => {
    const { response, config } = error;
    const isAuthRoute = config?.url?.includes('/auth/');
    if (
      response?.status === 401 &&
      config &&
      !config._retry &&
      !isAuthRoute &&
      tokenStore.refresh
    ) {
      config._retry = true;
      try {
        refreshing = refreshing || doRefresh();
        const ok = await refreshing;
        refreshing = null;
        if (ok) {
          config.headers.Authorization = `Bearer ${tokenStore.access}`;
          return api(config);
        }
      } catch {
        refreshing = null;
      }
    }
    return Promise.reject(error);
  }
);

// Bare axios call (no interceptors) so refresh can't recurse through itself.
async function doRefresh() {
  try {
    const res = await axios.post(
      `${API_BASE_URL}/auth/refresh-token`,
      { refreshToken: tokenStore.refresh },
      { headers: { 'X-Client-Platform': 'web' } }
    );
    const d = res.data?.data;
    tokenStore.save(d.accessToken, d.refreshToken);
    return true;
  } catch (e) {
    // Only nuke the session when the server explicitly rejects the refresh
    // token; transient errors keep the user signed in for the next attempt.
    const s = e?.response?.status;
    if (s === 401 || s === 403) tokenStore.clear();
    return false;
  }
}
