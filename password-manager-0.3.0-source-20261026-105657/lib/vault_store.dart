import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:kdbx/kdbx.dart';
// Version-pinned internal API used only to bound untrusted KDF costs before read.
// ignore: implementation_imports
import 'package:kdbx/src/kdbx_header.dart' show KdbxHeader;
// ignore: implementation_imports
import 'package:kdbx/src/utils/byte_utils.dart' show ReaderHelper;

import 'account_entry.dart';
import 'input_validation.dart';

const _formatKey = 'PasswordManager.Format';
const _pinKey = 'PasswordManager.EntryPin';
const _maxVaultBytes = 16 * 1024 * 1024;

class VaultException implements Exception {
  const VaultException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// KDBX 4, AES-256 and Argon2d (the KDF supported by kdbx 2.5.0).
/// All I/O is encrypted. No master password is written to disk.
Future<Uint8List> _encodeVault(Map<String, Object> input) async {
  final file = KdbxFormat().create(
    Credentials(ProtectedValue.fromString(input['master'] as String)),
    'Password Manager',
  );
  try {
    final parameters = file.header.readKdfParameters;
    KdfField.memory.write(parameters, 64 * 1024 * 1024);
    KdfField.iterations.write(parameters, 3);
    KdfField.parallelism.write(parameters, 1);
    file.header.writeKdfParameters(parameters);
    file.body.meta.customData[_formatKey] = '1';
    file.body.meta.customData[_pinKey] = input['pin'] as String;
    final group = file.body.rootGroup;
    for (final values in input['entries'] as List<Map<String, String>>) {
      final entry = KdbxEntry.create(file, group);
      group.addEntry(entry);
      entry.customData['PasswordManager.Id'] = values['id']!;
      entry.setString(
        KdbxKeyCommon.TITLE,
        ProtectedValue.fromString(values['name']!),
      );
      entry.setString(
        KdbxKeyCommon.USER_NAME,
        ProtectedValue.fromString(values['username']!),
      );
      entry.setString(
        KdbxKeyCommon.PASSWORD,
        ProtectedValue.fromString(values['password']!),
      );
      entry.setString(
        KdbxKeyCommon.URL,
        ProtectedValue.fromString(values['url']!),
      );
      entry.setString(
        KdbxKey('Notes'),
        ProtectedValue.fromString(values['notes']!),
      );
      entry.setString(
        KdbxKey('PasswordManager.History'),
        ProtectedValue.fromString(values['history'] ?? '[]'),
      );
      entry.customData['PasswordManager.ModifiedAt'] =
          values['modifiedAt'] ?? '';
    }
    return await file.save();
  } finally {
    file.dispose();
  }
}

Future<Map<String, Object>> _decodeVault(Map<String, Object> input) async {
  final bytes = input['bytes'] as Uint8List;
  // Do not let an edited header request unbounded memory/work before its MAC
  // can be checked. Only the app's explicitly supported KDBX profile is opened.
  final header = KdbxHeader.read(ReaderHelper(bytes));
  if (header.version != KdbxVersion.V4) {
    throw const VaultException('Versión de bóveda no admitida.');
  }
  final parameters = header.readKdfParameters;
  if (KeyEncrypterKdf.kdfTypeFor(parameters) != KdfType.Argon2 ||
      KdfField.memory.read(parameters) != 64 * 1024 * 1024 ||
      KdfField.iterations.read(parameters) != 3 ||
      KdfField.parallelism.read(parameters) != 1 ||
      KdfField.version.read(parameters) != 0x13) {
    throw const VaultException(
      'Configuración de cifrado no admitida por esta versión.',
    );
  }
  final file = await KdbxFormat().read(
    bytes,
    Credentials(ProtectedValue.fromString(input['master'] as String)),
  );
  try {
    if (file.body.meta.customData[_formatKey] != '1') {
      throw const VaultException(
        'Esta versión solo abre bóvedas creadas por esta aplicación.',
      );
    }
    final pin = file.body.meta.customData[_pinKey];
    if (!RegExp(r'^[0-9]{8}$').hasMatch(pin ?? '')) {
      throw const VaultException('La configuración del PIN no es válida.');
    }
    final entries = file.body.rootGroup
        .getAllEntries()
        .map(
          (entry) => <String, String>{
            'id':
                entry.customData['PasswordManager.Id'] ?? entry.uuid.toString(),
            'name': entry.getString(KdbxKeyCommon.TITLE)?.getText() ?? '',
            'username':
                entry.getString(KdbxKeyCommon.USER_NAME)?.getText() ?? '',
            'password':
                entry.getString(KdbxKeyCommon.PASSWORD)?.getText() ?? '',
            'url': entry.getString(KdbxKeyCommon.URL)?.getText() ?? '',
            'notes': entry.getString(KdbxKey('Notes'))?.getText() ?? '',
            'history':
                entry
                    .getString(KdbxKey('PasswordManager.History'))
                    ?.getText() ??
                '[]',
            'modifiedAt': entry.customData['PasswordManager.ModifiedAt'] ?? '',
          },
        )
        .toList();
    _validateEntries(entries.map(AccountEntry.fromMap).toList());
    return {'pin': pin!, 'entries': entries};
  } finally {
    file.dispose();
  }
}

void _validateEntries(List<AccountEntry> entries) {
  final ids = <String>{};
  var textSize = 0;
  for (final entry in entries) {
    if (entry.id.isEmpty || entry.id.length > 128 || !ids.add(entry.id)) {
      throw const VaultException(
        'La identificación de las cuentas no es válida.',
      );
    }
    for (final version in [entry, ...entry.history]) {
      final error = InputValidation.entry(version);
      if (error != null) throw VaultException(error);
      textSize +=
          version.name.length +
          version.username.length +
          version.password.length +
          version.url.length +
          version.notes.length;
      if (textSize > 8 * 1024 * 1024) {
        throw const VaultException(
          'El contenido de la bóveda supera el límite admitido.',
        );
      }
    }
  }
}

class VaultStore {
  VaultStore(this.path);
  final String path;
  ProtectedValue? _master;
  String? _pin;
  String? _fingerprint;
  List<AccountEntry> _entries = [];
  bool _saving = false;
  RandomAccessFile? _fileLock;
  bool get unlocked => _master != null;
  String? get pin => _pin;
  List<AccountEntry> get entries => List.unmodifiable(_entries);
  String get backupPath => '$path.bak';

  static String defaultPath() {
    if (!Platform.isWindows) {
      throw const VaultException(
        'El almacenamiento móvil se integrará en la siguiente etapa.',
      );
    }
    final local = Platform.environment['LOCALAPPDATA'];
    if (local == null) {
      throw const VaultException('No se encontró la carpeta local de datos.');
    }
    return '$local${Platform.pathSeparator}PasswordManager${Platform.pathSeparator}vault.kdbx';
  }

  Future<void> _acquireLock() async {
    await File(path).parent.create(recursive: true);
    final handle = await File('$path.lock').open(mode: FileMode.append);
    try {
      await handle.lock(FileLock.exclusive);
    } catch (_) {
      await handle.close();
      throw const VaultException(
        'La bóveda está abierta en otra instancia. Cerrala antes de continuar.',
      );
    }
    _fileLock = handle;
  }

  Future<void> create(String master, String pin) async {
    if (unlocked) throw const VaultException('Ya hay una bóveda abierta.');
    final masterError = InputValidation.bounded(
      master,
      'La contraseña maestra',
      InputValidation.maxMasterLength,
    );
    if (masterError != null) throw VaultException(masterError);
    if (master.runes.length < 16 ||
        RegExp(r'^[0-9]+$').hasMatch(master) ||
        master.trim().isEmpty) {
      throw const VaultException(
        'Usá una frase maestra larga, de al menos 16 caracteres, que no sea solo numérica.',
      );
    }
    if (!RegExp(r'^[0-9]{8}$').hasMatch(pin)) {
      throw const VaultException('El PIN debe tener ocho dígitos.');
    }
    await _acquireLock();
    try {
      if (await File(path).exists()) {
        throw const VaultException(
          'Ya existe una bóveda en esa ubicación. Abrila para continuar.',
        );
      }
      _master = ProtectedValue.fromString(master);
      _pin = pin;
      await save([]);
    } catch (_) {
      await lock();
      rethrow;
    }
  }

  Future<void> open(String master) async {
    if (unlocked) throw const VaultException('Ya hay una bóveda abierta.');
    final masterError = InputValidation.bounded(
      master,
      'La contraseña maestra',
      InputValidation.maxMasterLength,
    );
    if (masterError != null) throw VaultException(masterError);
    // A typo in the path must not create an empty vault.
    if (!await File(path).exists()) {
      throw const VaultException('No se encontró la bóveda en esa ubicación.');
    }
    await _acquireLock();
    try {
      final bytes = await _readBounded();
      final input = <String, Object>{'bytes': bytes, 'master': master};
      final data = await Isolate.run(() => _decodeVault(input));
      _master = ProtectedValue.fromString(master);
      _pin = data['pin'] as String;
      _entries = (data['entries'] as List<Map<String, String>>)
          .map(AccountEntry.fromMap)
          .toList();
      _fingerprint = sha256.convert(bytes).toString();
    } catch (error) {
      await lock();
      if (error is VaultException) rethrow;
      throw const VaultException(
        'No se pudo abrir: contraseña incorrecta o archivo dañado.',
      );
    }
  }

  Future<Uint8List> _readBounded() async {
    final file = File(path);
    if (await file.length() > _maxVaultBytes) {
      throw const VaultException('El archivo supera el tamaño admitido.');
    }
    final bytes = await file.readAsBytes();
    if (bytes.length > _maxVaultBytes) {
      throw const VaultException('El archivo supera el tamaño admitido.');
    }
    return bytes;
  }

  Future<void> _checkUnchanged() async {
    final exists = await File(path).exists();
    if (_fingerprint == null ? exists : !exists) {
      throw const VaultException(
        'El archivo cambió fuera de la aplicación. Volvé a abrirlo antes de guardar.',
      );
    }
    if (exists &&
        sha256.convert(await _readBounded()).toString() != _fingerprint) {
      throw const VaultException(
        'El archivo cambió fuera de la aplicación. Volvé a abrirlo antes de guardar.',
      );
    }
  }

  Future<void> save(List<AccountEntry> entries) async {
    await _save(entries);
  }

  Future<void> changeCredentials({
    required String currentMaster,
    String? newMaster,
    String? newPin,
  }) async {
    if (!unlocked || currentMaster != _master!.getText()) {
      throw const VaultException(
        'La contraseña maestra actual no es correcta.',
      );
    }
    final master = newMaster ?? currentMaster;
    final pin = newPin ?? _pin!;
    final masterError = InputValidation.bounded(
      master,
      'La contraseña maestra',
      InputValidation.maxMasterLength,
    );
    if (masterError != null) throw VaultException(masterError);
    if (master.runes.length < 16 ||
        RegExp(r'^[0-9]+$').hasMatch(master) ||
        master.trim().isEmpty) {
      throw const VaultException(
        'Usá una frase maestra de al menos 16 caracteres, que no sea solo numérica.',
      );
    }
    if (!RegExp(r'^[0-9]{8}$').hasMatch(pin)) {
      throw const VaultException('El PIN debe tener ocho dígitos.');
    }
    await _save(_entries, master: master, pin: pin);
  }

  Future<void> _save(
    List<AccountEntry> entries, {
    String? master,
    String? pin,
  }) async {
    if (!unlocked || _pin == null) {
      throw const VaultException('La bóveda está bloqueada.');
    }
    if (_saving) throw const VaultException('Hay un guardado en curso.');
    _saving = true;
    try {
      _validateEntries(entries);
      final previous = {for (final entry in _entries) entry.id: entry};
      entries = entries
          .map((entry) => entry.withPrevious(previous[entry.id]))
          .toList();
      _validateEntries(entries);
      await _checkUnchanged();
      final input = <String, Object>{
        'master': master ?? _master!.getText(),
        'pin': pin ?? _pin!,
        'entries': entries.map((entry) => entry.toMap()).toList(),
      };
      final encrypted = await Isolate.run(() => _encodeVault(input));
      if (encrypted.length > _maxVaultBytes) {
        throw const VaultException(
          'La bóveda supera el tamaño admitido. No se guardaron los cambios.',
        );
      }
      await _checkUnchanged();
      final temporary = File('$path.pending');
      await temporary.writeAsBytes(encrypted, flush: true);
      if (await File(path).exists()) {
        // Copy the old encrypted bytes before replacement. A backup failure
        // aborts the save and leaves the current vault untouched.
        await File(path).copy('$backupPath.pending');
        await File('$backupPath.pending').rename(backupPath);
      }
      await _checkUnchanged();
      await temporary.rename(path);
      _fingerprint = sha256.convert(encrypted).toString();
      _entries = List.of(entries);
      if (master != null) _master = ProtectedValue.fromString(master);
      if (pin != null) _pin = pin;
    } finally {
      _saving = false;
    }
  }

  /// Exports only the authenticated encrypted file; never overwrites a file.
  Future<void> exportBackup(String destination) async {
    if (!unlocked || _saving) {
      throw const VaultException(
        'Desbloqueá la bóveda y esperá a que termine el guardado.',
      );
    }
    _saving = true;
    var created = false;
    final output = File(destination);
    try {
      await _checkUnchanged();
      final bytes = await _readBounded();
      if (sha256.convert(bytes).toString() != _fingerprint) {
        throw const VaultException('El archivo cambió fuera de la aplicación.');
      }
      await output.create(exclusive: true);
      created = true;
      await output.writeAsBytes(bytes, flush: true);
      if (sha256.convert(await output.readAsBytes()).toString() !=
          _fingerprint) {
        throw const VaultException('No se pudo verificar la copia.');
      }
    } catch (_) {
      if (created && await output.exists()) await output.delete();
      rethrow;
    } finally {
      _saving = false;
    }
  }

  /// Validates the backup before touching the current file. Keeps the current
  /// encrypted bytes under a unique name, even if that file is damaged.
  static Future<void> restoreBackup({
    required String source,
    required String destination,
    required String master,
  }) async {
    final masterError = InputValidation.bounded(
      master,
      'La contraseña maestra',
      InputValidation.maxMasterLength,
    );
    if (masterError != null) throw VaultException(masterError);
    final bytes = await VaultStore(source)._readBounded();
    final input = <String, Object>{'bytes': bytes, 'master': master};
    try {
      await Isolate.run(() => _decodeVault(input));
    } catch (_) {
      throw const VaultException(
        'No se pudo validar la copia: contraseña incorrecta o archivo dañado.',
      );
    }
    final target = VaultStore(destination);
    await target._acquireLock();
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final temporary = File('$destination.restore-$stamp.pending');
    try {
      await temporary.create(exclusive: true);
      await temporary.writeAsBytes(bytes, flush: true);
      if (await File(destination).exists()) {
        final original = await target._readBounded();
        final preserved = File('$destination.before-restore-$stamp.kdbx');
        await preserved.create(exclusive: true);
        await preserved.writeAsBytes(original, flush: true);
        if (sha256.convert(await target._readBounded()).toString() !=
            sha256.convert(original).toString()) {
          throw const VaultException(
            'La bóveda cambió durante la restauración. No se reemplazó.',
          );
        }
      }
      await temporary.rename(destination);
    } finally {
      if (await temporary.exists()) await temporary.delete();
      await target.lock();
    }
  }

  Future<void> lock() async {
    if (_saving) {
      throw const VaultException('Esperá a que termine el guardado.');
    }
    _master = null;
    _pin = null;
    _entries = [];
    _fingerprint = null;
    final handle = _fileLock;
    _fileLock = null;
    if (handle != null) {
      try {
        await handle.unlock();
      } finally {
        await handle.close();
      }
    }
  }
}
