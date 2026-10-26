import 'dart:math';

/// Uses secure randomness and rejection sampling to include each enabled class.
/// When enabled, symbols are limited to one or two per password.
String generatePassword({int length = 24, bool symbols = true}) {
  if (length < 20 || length > 30) {
    throw ArgumentError.value(length, 'length', 'Debe estar entre 20 y 30');
  }
  final groups = [
    'abcdefghijklmnopqrstuvwxyz',
    'ABCDEFGHIJKLMNOPQRSTUVWXYZ',
    '0123456789',
    if (symbols) '!@#\$%^&*()-_=+[]{}:,.?',
  ];
  final alphabet = groups.join();
  final random = Random.secure();
  while (true) {
    final characters = List.generate(
      length,
      (_) => alphabet[random.nextInt(alphabet.length)],
    );
    final symbolCount = characters
        .where((character) => !RegExp(r'^[a-zA-Z0-9]$').hasMatch(character))
        .length;
    if (groups.every((group) => characters.any(group.contains)) &&
        (!symbols || symbolCount <= 2)) {
      return characters.join();
    }
  }
}
