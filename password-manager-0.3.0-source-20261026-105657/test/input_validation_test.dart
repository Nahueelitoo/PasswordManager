import 'package:flutter_test/flutter_test.dart';
import 'package:password_manager/input_validation.dart';
import 'package:password_manager/account_entry.dart';

void main() {
  test('Entry validation rejects missing required fields, null characters and oversized fields', () {
    expect(
      InputValidation.entry(AccountEntry(' ', '', 'clave', '', '')),
      isNotNull,
    );
    expect(
      InputValidation.entry(AccountEntry('Servicio', '', '', '', '')),
      isNotNull,
    );
    expect(
      InputValidation.entry(
        AccountEntry('Servicio', '', 'clave\u0000', '', ''),
      ),
      isNotNull,
    );
    expect(
      InputValidation.entry(AccountEntry('x' * 201, '', 'clave', '', '')),
      isNotNull,
    );
    expect(
      InputValidation.entry(
        AccountEntry('Servicio', 'x' * 1025, 'clave', '', ''),
      ),
      isNotNull,
    );
    expect(
      InputValidation.entry(AccountEntry('Servicio', '', 'x' * 4097, '', '')),
      isNotNull,
    );
    expect(
      InputValidation.entry(
        AccountEntry('Servicio', '', 'clave', 'x' * 2049, ''),
      ),
      isNotNull,
    );
    expect(
      InputValidation.entry(
        AccountEntry('Servicio', '', 'clave', '', 'x' * 20001),
      ),
      isNotNull,
    );
  });

  test(
    'Validation preserves valid passwords and treats addresses as plain text',
    () {
      final entry = AccountEntry(
        'Servicio',
        '',
        '  clave con espacios  ',
        r'\\servidor\recurso',
        '<texto privado>',
      );
      expect(InputValidation.entry(entry), isNull);
      expect(entry.password, '  clave con espacios  ');
      expect(
        InputValidation.bounded(
          'x' * 1025,
          'La contraseña maestra',
          InputValidation.maxMasterLength,
        ),
        isNotNull,
      );
    },
  );
}
