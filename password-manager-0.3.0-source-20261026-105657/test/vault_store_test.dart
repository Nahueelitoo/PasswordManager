import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:password_manager/account_entry.dart';
import 'package:password_manager/vault_store.dart';

void main() {
  const master = 'frase ficticia larga para las pruebas 2026';
  late Directory fixtureDirectory;
  late Uint8List fixture;
  late Uint8List previous;
  late Directory directory;
  late VaultStore store;

  setUpAll(() async {
    fixtureDirectory = await Directory.systemTemp.createTemp(
      'pm-vault-fixture-',
    );
    final vault = VaultStore('${fixtureDirectory.path}/test.kdbx');
    await vault.create(master, '12345678');
    await vault.save([
      AccountEntry(
        'Servicio ficticio',
        'prueba@example.org',
        'secreto-ficticio-123',
        'https://example.org',
        'nota privada de prueba',
        id: 'account-one',
      ),
    ]);
    previous = await File(vault.path).readAsBytes();
    await vault.save([
      AccountEntry(
        'Servicio editado',
        'prueba@example.org',
        'otro-secreto-ficticio-456',
        'https://example.org',
        'nota privada de prueba',
        id: 'account-one',
      ),
    ]);
    fixture = await File(vault.path).readAsBytes();
    await vault.lock();
  });
  tearDownAll(() async => fixtureDirectory.delete(recursive: true));
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('pm-vault-test-');
    store = VaultStore('${directory.path}/vault.kdbx');
    await File(store.path).writeAsBytes(fixture);
  });
  tearDown(() async {
    await store.lock();
    await directory.delete(recursive: true);
  });

  test(
    'Encrypted file persists entries and PIN and drops references on lock',
    () async {
      final text = String.fromCharCodes(fixture);
      for (final secret in [
        'Servicio editado',
        'prueba@example.org',
        'otro-secreto-ficticio-456',
        '12345678',
        master,
      ]) {
        expect(text.contains(secret), isFalse);
      }
      await store.open(master);
      expect(store.pin, '12345678');
      expect(store.entries.single.name, 'Servicio editado');
      expect(store.entries.single.id, 'account-one');
      expect(store.entries.single.username, 'prueba@example.org');
      expect(store.entries.single.password, 'otro-secreto-ficticio-456');
      await store.lock();
      expect(store.entries, isEmpty);
      expect(store.pin, isNull);
      expect(store.unlocked, isFalse);
      await expectLater(store.save([]), throwsA(isA<VaultException>()));
    },
  );

  test('Invalid entries and duplicate identifiers are rejected before changing disk or memory', () async {
    await store.open(master);
    for (final entries in [
      [AccountEntry(' ', '', 'ficticia', '', '')],
      [AccountEntry('Servicio', '', 'x' * 4097, '', '')],
      [
        AccountEntry('Uno', '', 'ficticia', '', '', id: 'same'),
        AccountEntry('Dos', '', 'ficticia', '', '', id: 'same'),
      ],
    ]) {
      await expectLater(store.save(entries), throwsA(isA<VaultException>()));
      expect(await File(store.path).readAsBytes(), fixture);
      expect(store.entries.single.name, 'Servicio editado');
    }
  });

  test('Wrong master and tampered ciphertext are rejected without modifying the file', () async {
    await expectLater(
      store.open('una contraseña equivocada'),
      throwsA(isA<VaultException>()),
    );
    expect(store.unlocked, isFalse);
    expect(await File(store.path).readAsBytes(), fixture);
    final altered = Uint8List.fromList(fixture);
    altered[altered.length - 20] ^= 1;
    await File(store.path).writeAsBytes(altered);
    await expectLater(store.open(master), throwsA(isA<VaultException>()));
    expect(await File(store.path).readAsBytes(), altered);
  });

  test(
    'Backup contains previous encrypted version and can be restored',
    () async {
      final file = File('${fixtureDirectory.path}/test.kdbx.bak');
      expect(await file.readAsBytes(), previous);
      await File(store.path).writeAsBytes(await file.readAsBytes());
      await store.open(master);
      expect(store.entries.single.name, 'Servicio ficticio');
      expect(store.entries.single.password, 'secreto-ficticio-123');
    },
  );

  test(
    'A failed backup aborts save and preserves both disk and memory',
    () async {
      await store.open(master);
      await Directory('${store.backupPath}.pending').create();
      await expectLater(store.save([]), throwsA(isA<FileSystemException>()));
      expect(await File(store.path).readAsBytes(), fixture);
      expect(store.entries.single.name, 'Servicio editado');
    },
  );

  test('External changes are not overwritten and creation never replaces an existing vault', () async {
    await expectLater(
      store.create(master, '12345678'),
      throwsA(isA<VaultException>()),
    );
    expect(await File(store.path).readAsBytes(), fixture);
    await store.open(master);
    final external = Uint8List.fromList(fixture)..[20] ^= 1;
    await File(store.path).writeAsBytes(external);
    await expectLater(store.save([]), throwsA(isA<VaultException>()));
    expect(await File(store.path).readAsBytes(), external);
  });

  test('Credential change requires the current master and persists new credentials', () async {
    await store.open(master);
    const replacement = 'otra frase maestra ficticia completamente distinta';
    await expectLater(
      store.changeCredentials(
        currentMaster: 'incorrecta',
        newMaster: replacement,
      ),
      throwsA(isA<VaultException>()),
    );
    expect(await File(store.path).readAsBytes(), fixture);
    await store.changeCredentials(
      currentMaster: master,
      newMaster: replacement,
      newPin: '87654321',
    );
    expect(store.pin, '87654321');
    await store.lock();
    await expectLater(store.open(master), throwsA(isA<VaultException>()));
    await store.open(replacement);
    expect(store.pin, '87654321');
    expect(store.entries.single.name, 'Servicio editado');
    final backup = VaultStore(store.backupPath);
    try {
      await backup.open(master);
      expect(backup.pin, '12345678');
    } finally {
      await backup.lock();
    }
  });

  test(
    'Failed credential change leaves the original master and PIN usable',
    () async {
      await store.open(master);
      await Directory('${store.backupPath}.pending').create();
      await expectLater(
        store.changeCredentials(
          currentMaster: master,
          newMaster: 'otra frase ficticia para cambio fallido',
          newPin: '87654321',
        ),
        throwsA(isA<FileSystemException>()),
      );
      expect(store.pin, '12345678');
      expect(await File(store.path).readAsBytes(), fixture);
      await store.lock();
      await store.open(master);
    },
  );

  test('PIN can change without changing the master', () async {
    await store.open(master);
    await store.changeCredentials(currentMaster: master, newPin: '87654321');
    await store.lock();
    await store.open(master);
    expect(store.pin, '87654321');
  });

  test(
    'Export is encrypted, verified and never overwrites an existing file',
    () async {
      await store.open(master);
      final output = '${directory.path}/external.kdbx';
      await store.exportBackup(output);
      expect(await File(output).readAsBytes(), fixture);
      await expectLater(
        store.exportBackup(output),
        throwsA(isA<FileSystemException>()),
      );
      expect(await File(output).readAsBytes(), fixture);
      await expectLater(
        store.exportBackup(store.path),
        throwsA(isA<FileSystemException>()),
      );
      expect(await File(store.path).readAsBytes(), fixture);
    },
  );

  test(
    'Restore authenticates the backup and preserves the prior encrypted vault',
    () async {
      final source = '${directory.path}/recover.kdbx';
      await File(source).writeAsBytes(previous);
      await VaultStore.restoreBackup(
        source: source,
        destination: store.path,
        master: master,
      );
      expect(await File(source).readAsBytes(), previous);
      final preserved = directory
          .listSync()
          .whereType<File>()
          .where((file) => file.path.contains('.before-restore-'))
          .single;
      expect(await preserved.readAsBytes(), fixture);
      await store.open(master);
      expect(store.entries.single.name, 'Servicio ficticio');
    },
  );

  test('Invalid restore and restore while in use leave the current vault unchanged', () async {
    final source = '${directory.path}/recover.kdbx';
    await File(source).writeAsBytes(previous);
    await expectLater(
      VaultStore.restoreBackup(
        source: source,
        destination: store.path,
        master: 'incorrecta',
      ),
      throwsA(isA<VaultException>()),
    );
    expect(await File(store.path).readAsBytes(), fixture);
    await store.open(master);
    await expectLater(
      VaultStore.restoreBackup(
        source: source,
        destination: store.path,
        master: master,
      ),
      throwsA(isA<VaultException>()),
    );
    expect(await File(store.path).readAsBytes(), fixture);
  });

  test(
    'Edits preserve encrypted history across saving and reopening',
    () async {
      await store.open(master);
      final old = store.entries.single;
      await store.save([
        AccountEntry(
          old.name,
          old.username,
          'nueva clave ficticia',
          old.url,
          old.notes,
          id: old.id,
        ),
      ]);
      expect(store.entries.single.history.first.password, old.password);
      expect(store.entries.single.modifiedAt, isNotNull);
      expect(
        String.fromCharCodes(await File(store.path).readAsBytes())
            .contains(old.password),
        isFalse,
      );
      await store.lock();
      await store.open(master);
      expect(store.entries.single.password, 'nueva clave ficticia');
      expect(store.entries.single.history.first.password, old.password);
      final count = store.entries.single.history.length;
      await store.save(store.entries);
      expect(store.entries.single.history.length, count);
    },
  );
}
