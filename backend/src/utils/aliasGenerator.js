// Generates the random "CobaltOwl"-style alias + colour handed to anonymous
// users when they join an ephemeral room. Nothing here persists — a user gets
// a fresh identity every time they enter a room.

import { ALIAS } from '../constants.js';

// Pick a uniformly random element from an array.
const pick = (arr) => arr[Math.floor(Math.random() * arr.length)];

/**
 * Produce a random alias, e.g. "CobaltOwl".
 * @returns {string}
 */
export const generateAlias = () => {
  const adjective = pick(ALIAS.ADJECTIVES);
  const animal = pick(ALIAS.ANIMALS);
  return `${adjective}${animal}`;
};

/**
 * Pick a random display colour for a user's alias/bubbles.
 * @returns {string} hex colour
 */
export const generateColor = () => pick(ALIAS.COLORS);

/**
 * Convenience: an alias and a colour together.
 * @returns {{ alias: string, color: string }}
 */
export const generateIdentity = () => ({
  alias: generateAlias(),
  color: generateColor(),
});
