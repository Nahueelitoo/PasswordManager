import 'package:flutter_test/flutter_test.dart';
import 'package:password_manager/password_generator.dart';

void main() {
  test('Generated passwords obey length and character requirements', () {
    for (final length in [20, 24, 30]) {
      for (var i = 0; i < 50; i++) {
        final value = generatePassword(length: length);
        expect(value.length, length);
        expect(RegExp('[a-z]').hasMatch(value), isTrue);
        expect(RegExp('[A-Z]').hasMatch(value), isTrue);
        expect(RegExp('[0-9]').hasMatch(value), isTrue);
        expect(RegExp('[^a-zA-Z0-9]').hasMatch(value), isTrue);
        expect(
          RegExp('[^a-zA-Z0-9]').allMatches(value).length,
          inInclusiveRange(1, 2),
        );
        expect(
          generatePassword(length: length, symbols: false),
          matches(RegExp(r'^[a-zA-Z0-9]+$')),
        );
      }
    }
  });
  test('Invalid lengths are rejected', () {
    expect(() => generatePassword(length: 0), throwsArgumentError);
    expect(() => generatePassword(length: 31), throwsArgumentError);
  });
}
