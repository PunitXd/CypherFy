// MongoDB connection helper.
// Called once at startup from src/index.js before the server begins listening.

import mongoose from 'mongoose';
import { DB_NAME } from '../constants.js';

const connectDB = async () => {
  try {
    // The URI in .env may or may not include the db name; append DB_NAME
    // so the same cluster can host multiple apps cleanly.
    const connectionInstance = await mongoose.connect(
      `${process.env.MONGODB_URI}`,
      { dbName: DB_NAME }
    );

    console.log(
      `MongoDB connected → host: ${connectionInstance.connection.host}`
    );
  } catch (error) {
    // A DB failure at boot is fatal — let the caller decide to exit.
    console.error('MongoDB connection error:', error);
    throw error;
  }
};

export default connectDB;
