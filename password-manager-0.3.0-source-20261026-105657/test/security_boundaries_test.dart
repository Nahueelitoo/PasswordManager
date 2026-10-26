import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kdbx/kdbx.dart';
// Pinned internal APIs to construct deliberately invalid headers without
// running expensive KDFs or generating real credential material.
// ignore: implementation_imports
import 'package:kdbx/src/kdbx_header.dart' show KdbxHeader;
// ignore: implementation_imports
import 'package:kdbx/src/utils/byte_utils.dart' show ReaderHelper, WriterHelper;
import 'package:password_manager/vault_store.dart';

void main() {
  const master = 'PUBLIC fictitious security boundary fixture';
  late Directory directory;
  late Uint8List valid;
  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp(
      'pm-security-boundaries-',
    );
    final store = VaultStore('${directory.path}/fixture.kdbx');
    await store.create(master, '12345678');
    valid = await File(store.path).readAsBytes();
    await store.lock();
  });
  tearDownAll(() => directory.delete(recursive: true));

  test(
    'Untrusted KDF increases are rejected before deriving any key',
    () async {
      for (var variant = 0; variant < 4; variant++) {
        final header = KdbxHeader.read(ReaderHelper(valid));
        final parameters = header.readKdfParameters;
        switch (variant) {
          case 0:
            KdfField.memory.write(parameters, 128 * 1024 * 1024);
          case 1:
            KdfField.iterations.write(parameters, 4);
          case 2:
            KdfField.parallelism.write(parameters, 2);
          case 3:
            KdfField.version.write(parameters, 0x10);
        }
        header.writeKdfParameters(parameters);
        final writer = WriterHelper();
        header.write(writer);
        final file = File('${directory.path}/profile-$variant.kdbx');
        final bytes = writer.output.toBytes();
        await file.writeAsBytes(bytes);
        final store = VaultStore(file.path);
        try {
          await expectLater(
            store.open(master),
            throwsA(
              isA<VaultException>().having(
                (error) => error.message,
                'message',
                contains('Configuración de cifrado no admitida'),
              ),
            ),
          );
          expect(store.unlocked, isFalse);
          expect(await file.readAsBytes(), bytes);
        } finally {
          await store.lock();
        }
      }
    },
  );

  test(
    'Truncated and malformed headers fail closed without overwriting files',
    () async {
      for (final length in [0, 1, 4, 8, 20, 64]) {
        final file = File('${directory.path}/truncated-$length.kdbx');
        final bytes = valid.sublist(0, length);
        await file.writeAsBytes(bytes);
        final store = VaultStore(file.path);
        try {
          await expectLater(store.open(master), throwsA(isA<VaultException>()));
          expect(store.unlocked, isFalse);
          expect(await file.readAsBytes(), bytes);
        } finally {
          await store.lock();
        }
      }
    },
  );

  test(
    'Oversized vault is rejected and its bytes are left untouched',
    () async {
      final file = File('${directory.path}/oversized.kdbx');
      final handle = await file.open(mode: FileMode.write);
      await handle.truncate(16 * 1024 * 1024 + 1);
      await handle.close();
      final store = VaultStore(file.path);
      try {
        await expectLater(
          store.open(master),
          throwsA(
            isA<VaultException>().having(
              (error) => error.message,
              'message',
              contains('tamaño admitido'),
            ),
          ),
        );
        expect(store.unlocked, isFalse);
        expect(await file.length(), 16 * 1024 * 1024 + 1);
      } finally {
        await store.lock();
      }
    },
  );
}
