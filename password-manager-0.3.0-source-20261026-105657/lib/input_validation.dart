import 'account_entry.dart';

class InputValidation {
  static const maxMasterLength = 1024;
  static const maxNameLength = 200;
  static const maxUsernameLength = 1024;
  static const maxPasswordLength = 4096;
  static const maxUrlLength = 2048;
  static const maxNotesLength = 20000;

  static String? bounded(
    String? value,
    String label,
    int maximum, {
    bool required = false,
  }) {
    if (required && (value == null || value.trim().isEmpty)) {
      return 'Ingresá $label';
    }
    if (value != null && value.runes.length > maximum) {
      return '$label admite hasta $maximum caracteres';
    }
    if (value?.contains('\u0000') ?? false) {
      return '$label contiene un carácter nulo no admitido';
    }
    return null;
  }

  static String? password(String? value) {
    if (value == null || value.isEmpty) {
      return 'Ingresá o generá una contraseña';
    }
    return bounded(value, 'La contraseña', maxPasswordLength);
  }

  static String? entry(AccountEntry entry) =>
      bounded(
        entry.name,
        'el nombre del servicio',
        maxNameLength,
        required: true,
      ) ??
      bounded(entry.username, 'El usuario', maxUsernameLength) ??
      password(entry.password) ??
      bounded(entry.url, 'La dirección', maxUrlLength) ??
      bounded(entry.notes, 'Las notas', maxNotesLength);
}
