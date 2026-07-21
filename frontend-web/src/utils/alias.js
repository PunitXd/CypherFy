// Client-side random alias for anonymous ephemeral rooms. Mirrors the backend
// word lists (constants.js ALIAS) so aliases feel consistent across clients.

const ADJECTIVES = [
  'Red', 'Blue', 'Swift', 'Dark', 'Bright', 'Silent', 'Bold', 'Calm',
  'Sharp', 'Keen', 'Wild', 'Frost', 'Storm', 'Solar', 'Lunar', 'Crisp',
  'Jade', 'Amber', 'Coral', 'Teal', 'Onyx', 'Sage', 'Azure', 'Ember',
  'Cobalt', 'Silver', 'Golden', 'Misty', 'Neon', 'Polar',
];
const ANIMALS = [
  'Fox', 'Owl', 'Wolf', 'Bear', 'Hawk', 'Lynx', 'Crow', 'Deer', 'Hare',
  'Mink', 'Seal', 'Ibis', 'Wren', 'Kite', 'Dove', 'Puma', 'Boar', 'Newt',
  'Vole', 'Mole', 'Finch', 'Crane', 'Raven', 'Otter', 'Bison', 'Moose',
  'Viper', 'Gecko', 'Stoat',
];

const pick = (arr) => arr[Math.floor(Math.random() * arr.length)];

export const generateAlias = () => `${pick(ADJECTIVES)}${pick(ANIMALS)}`;
