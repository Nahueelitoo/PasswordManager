import 'dart:io';

import 'package:password_manager/account_entry.dart';
import 'package:password_manager/vault_store.dart';

// Public, fictitious credentials for interoperability checks only.
const fixtureMaster = 'public fixture password for interoperability';

Future<void> main(List<String> arguments) async {
  if (arguments.single == 'create') {
    await Directory('build/interop').create(recursive: true);
    final path =
        'build/interop/from-dart-${DateTime.now().microsecondsSinceEpoch}.kdbx';
    final store = VaultStore(File(path).absolute.path);
    await store.create(fixtureMaster, '12345678');
    await store.save([
      AccountEntry(
        'Interoperability fixture',
        'demo@example.org',
        'fictional-entry-password',
        'https://example.org',
        'Fictitious notes',
      ),
    ]);
    await store.lock();
    await File('build/interop/latest-path.txt')
        .writeAsString(File(path).absolute.path);
    stdout.writeln('Created fictitious KDBX fixture.');
  } else {
    final store = VaultStore(
      File('build/interop/from-python.kdbx').absolute.path,
    );
    await store.open(fixtureMaster);
    if (store.entries.single.notes != 'Updated by independent implementation' ||
        store.pin != '12345678') {
      throw StateError('Independent round trip failed.');
    }
    await store.lock();
    stdout.writeln('Independent KDBX round trip passed.');
  }
}
