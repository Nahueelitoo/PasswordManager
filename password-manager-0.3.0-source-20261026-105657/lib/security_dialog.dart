import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'input_validation.dart';

class SecurityChange {
  SecurityChange(this.currentMaster, this.newMaster, this.newPin);
  final String currentMaster;
  final String? newMaster, newPin;
}

class SecurityDialog extends StatefulWidget {
  const SecurityDialog({super.key, required this.onSave});
  final Future<bool> Function(SecurityChange) onSave;
  @override
  State<SecurityDialog> createState() => _SecurityDialogState();
}

class _SecurityDialogState extends State<SecurityDialog> {
  final _form = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _master = TextEditingController();
  final _confirmation = TextEditingController();
  final _pin = TextEditingController();
  final _pinConfirmation = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [
      _current,
      _master,
      _confirmation,
      _pin,
      _pinConfirmation,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Widget _field(
    TextEditingController controller,
    String label,
    String? Function(String?) validator, {
    bool numeric = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: TextFormField(
      controller: controller,
      obscureText: true,
      enabled: !_busy,
      autocorrect: false,
      enableSuggestions: false,
      keyboardType: numeric
          ? TextInputType.number
          : TextInputType.visiblePassword,
      inputFormatters: numeric
          ? [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(8),
            ]
          : null,
      decoration: InputDecoration(labelText: label),
      validator: validator,
    ),
  );

  Future<void> _save() async {
    if (_busy || !_form.currentState!.validate()) return;
    if (_master.text.isEmpty && _pin.text.isEmpty) {
      setState(
        () => _error = 'Ingresá una nueva contraseña maestra o un nuevo PIN.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final saved = await widget.onSave(
      SecurityChange(
        _current.text,
        _master.text.isEmpty ? null : _master.text,
        _pin.text.isEmpty ? null : _pin.text,
      ),
    );
    if (!mounted) return;
    if (saved) {
      Navigator.pop(context, true);
    } else {
      setState(() {
        _busy = false;
        _error =
            'No se pudo guardar. Verificá la contraseña actual y reintentá.';
      });
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Cambiar contraseña maestra o PIN'),
    content: SizedBox(
      width: 500,
      child: SingleChildScrollView(
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Dejá vacío lo que quieras conservar. Al confirmar se bloquea la bóveda. Las copias anteriores conservan su contraseña y PIN anteriores.',
              ),
              const SizedBox(height: 20),
              _field(
                _current,
                'Contraseña maestra actual',
                (v) => v == null || v.isEmpty
                    ? 'Ingresá la contraseña actual'
                    : null,
              ),
              _field(_master, 'Nueva contraseña maestra (opcional)', (v) {
                final error = InputValidation.bounded(
                  v,
                  'La contraseña maestra',
                  InputValidation.maxMasterLength,
                );
                if (error != null) return error;
                if (v == null || v.isEmpty) return null;
                return v.runes.length < 16 ||
                        v.trim().isEmpty ||
                        RegExp(r'^[0-9]+$').hasMatch(v)
                    ? 'Usá una frase de al menos 16 caracteres, que no sea solo numérica'
                    : null;
              }),
              _field(
                _confirmation,
                'Repetir nueva contraseña maestra',
                (v) =>
                    v != _master.text ? 'Las contraseñas no coinciden' : null,
              ),
              _field(
                _pin,
                'Nuevo PIN (opcional)',
                (v) =>
                    v != null &&
                        v.isNotEmpty &&
                        !RegExp(r'^[0-9]{8}$').hasMatch(v)
                    ? 'Ingresá ocho dígitos'
                    : null,
                numeric: true,
              ),
              _field(
                _pinConfirmation,
                'Repetir nuevo PIN',
                (v) => v != _pin.text ? 'Los PIN no coinciden' : null,
                numeric: true,
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
    ),
    actions: [
      TextButton(
        onPressed: _busy ? null : () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      FilledButton(
        onPressed: _busy ? null : _save,
        child: Text(_busy ? 'Guardando…' : 'Guardar y bloquear'),
      ),
    ],
  );
}
