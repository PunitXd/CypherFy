import 'dart:math';

/// Client-side random alias generator for anonymous ephemeral rooms.
/// Mirrors the backend word lists so aliases feel consistent across users.
class AliasGenerator {
  AliasGenerator._();

  static const _adjectives = [
    'Red', 'Blue', 'Swift', 'Dark', 'Bright', 'Silent', 'Bold', 'Calm',
    'Sharp', 'Keen', 'Wild', 'Frost', 'Storm', 'Solar', 'Lunar', 'Crisp',
    'Jade', 'Amber', 'Coral', 'Teal', 'Onyx', 'Sage', 'Azure', 'Ember',
    'Cobalt', 'Silver', 'Golden', 'Misty', 'Neon', 'Polar',
  ];
  static const _animals = [
    'Fox', 'Owl', 'Wolf', 'Bear', 'Hawk', 'Lynx', 'Crow', 'Deer', 'Hare',
    'Mink', 'Seal', 'Ibis', 'Wren', 'Kite', 'Dove', 'Puma', 'Boar', 'Newt',
    'Vole', 'Mole', 'Finch', 'Crane', 'Raven', 'Otter', 'Bison', 'Moose',
    'Viper', 'Gecko', 'Stoat',
  ];

  static final _rng = Random();

  static String generate() {
    final adj = _adjectives[_rng.nextInt(_adjectives.length)];
    final animal = _animals[_rng.nextInt(_animals.length)];
    return '$adj$animal';
  }
}
