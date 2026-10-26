import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Prototype-only gate. This is not a vault key or protection against access
/// to process memory. Nothing is persisted across application launches.
class DemoPinGate extends ChangeNotifier {
  String? _pin;
  int _failures = 0;
  int cooldownSeconds = 0;
  Timer? _timer;

  bool get configured => _pin != null;

  void configure(String pin) {
    if (configured || !RegExp(r'^[0-9]{8}$').hasMatch(pin)) {
      throw StateError('PIN inválido o ya configurado');
    }
    _pin = pin;
  }

  bool verify(String pin) {
    if (!configured || cooldownSeconds > 0) return false;
    if (pin == _pin) {
      _failures = 0;
      return true;
    }
    _failures++;
    if (_failures >= 5) {
      _failures = 0;
      cooldownSeconds = 30;
      _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
        cooldownSeconds--;
        if (cooldownSeconds == 0) timer.cancel();
        notifyListeners();
      });
      notifyListeners();
    }
    return false;
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pin = null;
    super.dispose();
  }
}

class PinDialog extends StatefulWidget {
  const PinDialog({super.key, required this.gate});
  final DemoPinGate gate;

  @override
  State<PinDialog> createState() => _PinDialogState();
}

class _PinDialogState extends State<PinDialog> {
  final _pin = TextEditingController();
  final _confirmation = TextEditingController();
  final _form = GlobalKey<FormState>();
  String? _error;
  late final bool _setup = !widget.gate.configured;

  @override
  void dispose() {
    _pin.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  Widget _field(TextEditingController controller, String label) =>
      TextFormField(
        controller: controller,
        autofocus: controller == _pin,
        obscureText: true,
        autocorrect: false,
        enableSuggestions: false,
        keyboardType: TextInputType.number,
        maxLength: 8,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: InputDecoration(labelText: label),
        validator: (value) {
          if (!RegExp(r'^[0-9]{8}$').hasMatch(value ?? '')) {
            return 'Ingresá exactamente 8 dígitos';
          }
          if (controller == _confirmation && value != _pin.text) {
            return 'Los PIN no coinciden';
          }
          return null;
        },
        onFieldSubmitted: (_) => _submit(),
      );

  void _submit() {
    if (widget.gate.cooldownSeconds > 0 || !_form.currentState!.validate()) {
      return;
    }
    if (_setup) {
      widget.gate.configure(_pin.text);
    } else if (!widget.gate.verify(_pin.text)) {
      _pin.clear();
      setState(() => _error = 'PIN incorrecto');
      return;
    }
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.gate,
    builder: (context, _) => AlertDialog(
      title: Text(_setup ? 'Crear PIN de prueba' : 'Ingresá tu PIN'),
      content: SizedBox(
        width: 360,
        child: SingleChildScrollView(
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _setup
                      ? 'Elegí un PIN de 8 números para todas las cuentas. Solo dura hasta cerrar la aplicación; usá un PIN ficticio.'
                      : 'Se solicita cada vez que abrís una cuenta.',
                ),
                const SizedBox(height: 20),
                _field(_pin, 'PIN de 8 dígitos'),
                if (_setup) ...[
                  const SizedBox(height: 12),
                  _field(_confirmation, 'Repetir PIN'),
                ],
                if (_error != null)
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                if (widget.gate.cooldownSeconds > 0)
                  Text(
                    'Demasiados intentos. Esperá ${widget.gate.cooldownSeconds} segundos.',
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: widget.gate.cooldownSeconds > 0 ? null : _submit,
          child: Text(_setup ? 'Crear PIN y continuar' : 'Abrir cuenta'),
        ),
      ],
    ),
  );
}
