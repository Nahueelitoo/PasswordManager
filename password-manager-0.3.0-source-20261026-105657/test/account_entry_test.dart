import 'package:flutter_test/flutter_test.dart';
import 'package:password_manager/account_entry.dart';

void main() {
  test('History keeps twenty immutable snapshots and round-trips', () {
    var entry = AccountEntry(
      'Servicio',
      'usuario',
      'ficticia 0',
      '',
      '',
      id: 'fixed',
    ).withPrevious(null);
    for (var i = 1; i <= 30; i++) {
      entry = AccountEntry(
        'Servicio',
        'usuario',
        'ficticia $i',
        '',
        '',
        id: entry.id,
      ).withPrevious(entry);
    }
    final restored = AccountEntry.fromMap(entry.toMap());
    expect(restored.history.length, 20);
    expect(restored.history.first.password, 'ficticia 29');
    expect(restored.history.last.password, 'ficticia 10');
    expect(restored.history.every((item) => item.history.isEmpty), isTrue);
    expect(restored.modifiedAt, entry.modifiedAt);
    expect(() => restored.history.clear(), throwsUnsupportedError);
  });
}
