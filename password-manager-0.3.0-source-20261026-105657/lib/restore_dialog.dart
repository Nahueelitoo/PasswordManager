import 'package:flutter/material.dart';

class RestoreDialog extends StatefulWidget {
  const RestoreDialog({super.key, required this.onRestore});
  final Future<void> Function(String) onRestore;
  @override
  State<RestoreDialog> createState() => _RestoreDialogState();
}

class _RestoreDialogState extends State<RestoreDialog> {
  final _master = TextEditingController();
  bool _confirmed = false, _busy = false;
  String? _error;
  @override
  void dispose() {
    _master.dispose();
    super.dispose();
  }

  Future<void> _restore() async {
    if (!_confirmed || _busy || _master.text.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onRestore(_master.text);
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'No se pudo restaurar. Verificá la contraseña de la copia, que el archivo sea válido y los permisos. La copia elegida no fue modificada.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Restaurar copia cifrada'),
    content: SizedBox(
      width: 470,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'La copia debe haber sido creada por esta aplicación. Se valida antes de restaurar. La bóveda actual se conserva en otro archivo cifrado y se reemplaza por la copia elegida. No se mezclan cuentas.',
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _master,
              obscureText: true,
              enabled: !_busy,
              autocorrect: false,
              enableSuggestions: false,
              decoration: const InputDecoration(
                labelText: 'Contraseña maestra de la copia',
              ),
            ),
            CheckboxListTile(
              value: _confirmed,
              onChanged: _busy
                  ? null
                  : (v) => setState(() => _confirmed = v ?? false),
              title: const Text(
                'Confirmo reemplazar la bóveda actual por esta copia',
              ),
            ),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: _busy ? null : () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      FilledButton(
        onPressed: _confirmed && !_busy ? _restore : null,
        child: Text(_busy ? 'Restaurando…' : 'Validar y restaurar'),
      ),
    ],
  );
}
