// Server entry point.
//
// Boot order (important): MongoDB → Redis → Socket.io (with Redis adapter) →
// HTTP listen. The Redis adapter needs a live Redis client, and the socket
// layer must be initialised before we accept connections.

// Load .env FIRST. ESM executes all imports before any other statement, so any
// module that reads process.env at load time (e.g. app.js's cors() setup) would
// see undefined unless dotenv runs during this import. Keeping it as the very
// first import guarantees the environment is populated before app.js loads.
import 'dotenv/config';

import { createServer } from 'http';

import { app } from './app.js';
import connectDB from './db/index.js';
import { connectRedis } from './services/redis.service.js';
import { initSocket } from './socket/index.js';

const httpServer = createServer(app);

connectDB()
  .then(() => connectRedis())
  .then(() => {
    // Attach Socket.io + Redis adapter before listening.
    initSocket(httpServer);

    const port = process.env.PORT || 8000;
    httpServer.listen(port, () => {
      console.log(`CypherFy running on port ${port}`);
    });
  })
  .catch((err) => {
    console.error('Startup failed:', err);
    process.exit(1);
  });

// Fail loudly on unexpected async errors rather than limping along.
process.on('unhandledRejection', (reason) => {
  console.error('Unhandled promise rejection:', reason);
});
