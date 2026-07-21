// ICE server configuration for WebRTC calls.
//
// STUN discovers your public address; TURN relays media when a direct P2P path
// can't be formed (symmetric NAT / cellular / restrictive firewalls). The server
// only hands out these addresses — it never relays media itself.
//
// Precedence:
//   1. If TURN_SERVER_URL is set in the env, use YOUR TURN server (production).
//   2. Otherwise fall back to Metered's free public "OpenRelay" TURN, so calls
//      work across networks out of the box. It's rate-limited and shared — fine
//      for testing/light use; swap in your own creds (env above) for production.
//      Metered free tier: https://dashboard.metered.ca (50 GB/mo).

const OPENRELAY_TURN = [
  {
    urls: 'turn:openrelay.metered.ca:80',
    username: 'openrelayproject',
    credential: 'openrelayproject',
  },
  {
    urls: 'turn:openrelay.metered.ca:443',
    username: 'openrelayproject',
    credential: 'openrelayproject',
  },
  {
    // TCP/443 looks like HTTPS — traverses the strictest corporate firewalls.
    urls: 'turn:openrelay.metered.ca:443?transport=tcp',
    username: 'openrelayproject',
    credential: 'openrelayproject',
  },
];

/** @returns {Array<{urls:string, username?:string, credential?:string}>} */
export const getIceServers = () => {
  // TURN_SERVER_URL may be a single URL or a comma-separated list sharing one
  // username/credential (e.g. Metered gives :80, :443 and a TCP transport).
  const turn = process.env.TURN_SERVER_URL
    ? process.env.TURN_SERVER_URL.split(',')
        .map((u) => u.trim())
        .filter(Boolean)
        .map((urls) => ({
          urls,
          username: process.env.TURN_USERNAME,
          credential: process.env.TURN_CREDENTIAL,
        }))
    : OPENRELAY_TURN;

  return [
    { urls: 'stun:stun.l.google.com:19302' },
    { urls: 'stun:stun1.l.google.com:19302' },
    ...turn,
  ];
};

/** Convenience wrapper matching the RTCConfiguration shape clients expect. */
export const getIceConfig = () => ({ iceServers: getIceServers() });
