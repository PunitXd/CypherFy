// Generates the 6-character room code (e.g. "XK9PLM") for ephemeral rooms.
// Uses nanoid with an unambiguous alphabet (no 0/O/1/I/L) so codes are easy
// to read aloud and type.

import { customAlphabet } from 'nanoid';
import { ROOM } from '../constants.js';

// Uppercase letters + digits, minus the visually ambiguous characters.
const ALPHABET = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';

const nanoid = customAlphabet(ALPHABET, ROOM.CODE_LENGTH);

/**
 * Generate an uppercase room code.
 * @returns {string} e.g. "XK9PLM"
 */
export const generateRoomCode = () => nanoid();
