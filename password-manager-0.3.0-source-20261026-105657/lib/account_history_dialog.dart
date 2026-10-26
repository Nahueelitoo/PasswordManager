import 'package:flutter/material.dart';

import 'account_entry.dart';
import 'clipboard_controller.dart';

class AccountHistoryDialog extends StatefulWidget {
  const AccountHistoryDialog({
    super.key,
    required this.entry,
    required this.clipboard,
  });
  final AccountEntry entry;
  final ClipboardController clipboard;
  @override
  State<AccountHistoryDialog> createState() => _AccountHistoryDialogState();
}

class _AccountHistoryDialogState extends State<AccountHistoryDialog> {
  final _visible = <int>{};
  Future<void> _copy(String value) async {
    try {
      await widget.clipboard.copy(value);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Contraseña anterior copiada. Se intentará limpiar en 30 segundos.',
            ),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('No se pudo copiar.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Historial cifrado de la cuenta'),
    content: SizedBox(
      width: 500,
      height: 400,
      child: ListView(
        children: [
          const Text(
            'Hasta 20 versiones anteriores. Copiar una contraseña anterior no la cambia en el servicio.',
          ),
          for (var i = 0; i < widget.entry.history.length; i++)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.entry.history[i].modifiedAt
                              ?.toLocal()
                              .toString()
                              .split('.')
                              .first ??
                          'Versión sin fecha registrada',
                    ),
                    Text(widget.entry.history[i].name),
                    Text(widget.entry.history[i].username),
                    if (widget.entry.history[i].url.isNotEmpty)
                      Text(widget.entry.history[i].url),
                    if (widget.entry.history[i].notes.isNotEmpty)
                      Text(widget.entry.history[i].notes),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _visible.contains(i)
                                ? widget.entry.history[i].password
                                : '••••••••',
                          ),
                        ),
                        IconButton(
                          tooltip: _visible.contains(i)
                              ? 'Ocultar contraseña anterior'
                              : 'Mostrar contraseña anterior',
                          onPressed: () => setState(() {
                            if (!_visible.add(i)) _visible.remove(i);
                          }),
                          icon: Icon(
                            _visible.contains(i)
                                ? Icons.visibility_off
                                : Icons.visibility,
                          ),
                        ),
                        IconButton(
                          tooltip: 'Copiar contraseña anterior',
                          onPressed: () =>
                              _copy(widget.entry.history[i].password),
                          icon: const Icon(Icons.copy),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cerrar'),
      ),
    ],
  );
}
