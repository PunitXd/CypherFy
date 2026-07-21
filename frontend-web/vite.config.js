import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

// Dev proxy: the backend only allows CORS from its configured CLIENT_URL. Instead
// of matching that, we run the app on :5173 and proxy all API + socket traffic
// through Vite — so the browser makes same-origin requests (no CORS), and Vite
// presents the backend's allowed Origin. No backend/container change needed.
//
// Override the target with BACKEND_ORIGIN / BACKEND_CLIENT_URL env vars if your
// backend runs elsewhere or allows a different origin.
const BACKEND = process.env.BACKEND_ORIGIN || 'http://localhost:8000'
// Present the dev origin so the backend's CORS (and its emailed reset link, which
// use the same CLIENT_URL) line up with where the browser actually is (:5173).
// For a dockerized backend (CLIENT_URL=:8080) set BACKEND_CLIENT_URL to match.
const ALLOWED_ORIGIN = process.env.BACKEND_CLIENT_URL || 'http://localhost:5173'

const presentAllowedOrigin = (proxy) => {
  proxy.on('proxyReq', (proxyReq) => proxyReq.setHeader('origin', ALLOWED_ORIGIN))
  proxy.on('proxyReqWs', (proxyReq) => proxyReq.setHeader('origin', ALLOWED_ORIGIN))
}

// https://vite.dev/config/
export default defineConfig({
  plugins: [react()],
  server: {
    proxy: {
      '/api': { target: BACKEND, changeOrigin: true, configure: presentAllowedOrigin },
      '/socket.io': { target: BACKEND, ws: true, changeOrigin: true, configure: presentAllowedOrigin },
    },
  },
})
