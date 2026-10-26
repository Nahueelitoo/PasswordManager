import 'package:flutter/material.dart';

import 'account_entry.dart';
import 'clipboard_controller.dart';

class AccountViewDialog extends StatefulWidget {
  const AccountViewDialog({
    super.key,
    required this.entry,
    required this.clipboard,
  });
  final AccountEntry entry;
  final ClipboardController clipboard;
  @override
  State<AccountViewDialog> createState() => _AccountViewDialogState();
}

class _AccountViewDialogState extends State<AccountViewDialog> {
  late final _name = TextEditingController(text: widget.entry.name);
  late final _username = TextEditingController(text: widget.entry.username);
  late final _password = TextEditingController(text: widget.entry.password);

  Future<void> _copy(String value) async {
    if (value.isEmpty) return;
    try {
      await widget.clipboard.copy(value);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Copiado. Se intentará limpiar el portapapeles en 30 segundos.',
          ),
          duration: Duration(seconds: 3),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo copiar al portapapeles.')),
      );
    }
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    String? copy,
    bool secret = false,
  }) => TextField(
    controller: controller,
    readOnly: true,
    enableInteractiveSelection: false,
    obscureText: secret,
    autocorrect: false,
    enableSuggestions: false,
    decoration: InputDecoration(
      labelText: label,
      suffixIcon: copy == null
          ? null
          : IconButton(
              tooltip: 'Copiar $copy',
              icon: const Icon(Icons.copy_outlined),
              onPressed: controller.text.isEmpty
                  ? null
                  : () => _copy(controller.text),
            ),
    ),
  );

  @override
  void dispose() {
    for (final c in [_name, _username, _password]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Consultar cuenta'),
    content: SizedBox(
      width: 460,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _field(_name, 'Nombre del servicio'),
            const SizedBox(height: 20),
            _field(_username, 'Usuario o correo electrónico', copy: 'usuario'),
            const SizedBox(height: 20),
            _field(
              _password,
              'Contraseña actual',
              copy: 'contraseña',
              secret: true,
            ),
          ],
        ),
      ),
    ),
    actions: [
      FilledButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cerrar'),
      ),
    ],
  );
}
