import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'main.dart' show AccountsPage;
import 'vault_store.dart';
import 'windows_services.dart';
import 'restore_dialog.dart';
import 'input_validation.dart';
import 'local_attempt_limiter.dart';

class VaultPage extends StatefulWidget {
  const VaultPage({super.key, this.initialPath, this.storeFactory});
  final String? initialPath;
  final VaultStore Function(String)? storeFactory;
  @override
  State<VaultPage> createState() => _VaultPageState();
}

class _VaultPageState extends State<VaultPage> with WidgetsBindingObserver {
  String? _path;
  final _master = TextEditingController();
  final _confirmation = TextEditingController();
  final _pin = TextEditingController();
  final _pinConfirmation = TextEditingController();
  final _form = GlobalKey<FormState>();
  VaultStore? _store;
  bool _create = true;
  bool _busy = false;
  bool _cancelOpen = false;
  final _attempts = LocalAttemptLimiter();
  String? _error;
  StreamSubscription<void>? _windowsLocks;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _windowsLocks = windowsLockRequests.listen(
      (_) => didChangeAppLifecycleState(AppLifecycleState.hidden),
    );
    _attempts.addListener(_refreshAttempts);
    try {
      _path = widget.initialPath ?? VaultStore.defaultPath();
      _create = !File(_path!).existsSync();
    } catch (_) {
      _error = 'La bóveda local está disponible en Windows. Android se integrará en la siguiente etapa.';
    }
  }

  @override
  void dispose() {
    _windowsLocks?.cancel();
    _attempts.dispose();
    WidgetsBinding.instance.removeObserver(this);
    final store = _store;
    if (store != null) unawaited(store.lock().catchError((_) {}));
    for (final controller in [_master, _confirmation, _pin, _pinConfirmation]) {
      controller.dispose();
    }
    super.dispose();
  }

  void _refreshAttempts() {
    if (mounted) setState(() {});
  }

  void _clearSecrets() {
    for (final controller in [_master, _confirmation, _pin, _pinConfirmation]) {
      controller.clear();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused) {
      _cancelOpen = true;
      _clearSecrets();
      if (_store == null) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    }
  }

  Future<void> _restore() async {
    if (_busy || _path == null || _attempts.cooldownSeconds > 0) return;
    _cancelOpen = false;
    try {
      final source = await chooseBackupFile();
      if (source == null || !mounted || _cancelOpen) return;
      final restored = await showDialog<bool>(
        animationStyle: AnimationStyle.noAnimation,
        context: context,
        barrierDismissible: false,
        builder: (_) => RestoreDialog(
          onRestore: (master) async {
            if (_attempts.cooldownSeconds > 0) {
              throw const VaultException('Esperá antes de reintentar.');
            }
            setState(() => _busy = true);
            try {
              await VaultStore.restoreBackup(
                source: source,
                destination: _path!,
                master: master,
              );
              if (mounted) _attempts.success();
              if (mounted) setState(() => _create = false);
            } catch (_) {
              if (mounted) _attempts.failure();
              rethrow;
            } finally {
              if (mounted) setState(() => _busy = false);
            }
          },
        ),
      );
      if (restored == true && mounted) {
        setState(
          () => _error = 'Copia restaurada. Desbloqueá con la contraseña maestra de esa copia.',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'No se pudo seleccionar la copia cifrada.');
      }
    }
  }

  Future<void> _lock() async {
    Navigator.of(context).popUntil((route) => route.isFirst);
    try {
      await _store?.lock();
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'La bóveda quedó bloqueada, pero no se pudo liberar el archivo. Cerrá y volvé a abrir la aplicación.',
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _store = null;
          _create = false;
        });
      }
    }
  }

  Future<void> _submit() async {
    if (_busy ||
        _path == null ||
        _attempts.cooldownSeconds > 0 ||
        !_form.currentState!.validate()) {
      return;
    }
    setState(() {
      _busy = true;
      _cancelOpen = false;
      _error = null;
    });
    final store = (widget.storeFactory ?? VaultStore.new)(_path!);
    try {
      if (_create) {
        await store.create(_master.text, _pin.text);
      } else {
        await store.open(_master.text);
      }
      _attempts.success();
      if (!mounted || _cancelOpen) {
        await store.lock();
        if (mounted) {
          setState(() {
            _create = false;
            _error = 'La bóveda quedó bloqueada al ocultar la aplicación.';
          });
        }
        return;
      }
      _clearSecrets();
      setState(() => _store = store);
    } catch (error) {
      if (mounted) {
        if (!_create) _attempts.failure();
        setState(
          () => _error = error is VaultException ? error.message : 'No se pudo acceder al archivo. Revisá la ubicación y los permisos.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _secret(
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
      onFieldSubmitted: (_) => _submit(),
    ),
  );

  @override
  Widget build(BuildContext context) {
    if (_store != null) return AccountsPage(store: _store, onLock: _lock);
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Password Manager',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineLarge
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 24),
                  const Icon(Icons.lock_outline, size: 48),
                  const SizedBox(height: 16),
                  Text(
                    'Tu bóveda local',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 24),
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: true, label: Text('Crear bóveda')),
                      ButtonSegment(value: false, label: Text('Abrir bóveda')),
                    ],
                    selected: {_create},
                    onSelectionChanged: _busy
                        ? null
                        : (value) => setState(() {
                            _create = value.first;
                            _error = null;
                            _form.currentState?.reset();
                          }),
                  ),
                  const SizedBox(height: 24),
                  _secret(_master, 'Contraseña maestra', (value) {
                    final error = InputValidation.bounded(
                      value,
                      'La contraseña maestra',
                      InputValidation.maxMasterLength,
                    );
                    if (error != null) return error;
                    if (value == null || value.isEmpty) {
                      return 'Ingresá la contraseña maestra';
                    }
                    if (_create &&
                        (value.runes.length < 16 ||
                            RegExp(r'^[0-9]+$').hasMatch(value) ||
                            value.trim().isEmpty)) {
                      return 'Usá una frase de al menos 16 caracteres, que no sea solo numérica';
                    }
                    return null;
                  }),
                  if (_create) ...[
                    _secret(
                      _confirmation,
                      'Repetir contraseña maestra',
                      (value) => value != _master.text
                          ? 'Las contraseñas no coinciden'
                          : null,
                    ),
                    _secret(
                      _pin,
                      'PIN para entrar a las cuentas (8 dígitos)',
                      (value) => !RegExp(r'^[0-9]{8}$').hasMatch(value ?? '')
                          ? 'Ingresá exactamente ocho dígitos'
                          : null,
                      numeric: true,
                    ),
                    _secret(
                      _pinConfirmation,
                      'Repetir PIN',
                      (value) =>
                          value != _pin.text ? 'Los PIN no coinciden' : null,
                      numeric: true,
                    ),
                    const Text(
                      'Conservá la contraseña maestra en un lugar seguro: no hay restablecimiento por correo. El PIN no reemplaza esa contraseña.',
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  FilledButton.icon(
                    onPressed:
                        _busy || _path == null || _attempts.cooldownSeconds > 0
                        ? null
                        : _submit,
                    icon: _busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.lock_open),
                    label: Text(
                      _busy
                          ? 'Procesando…'
                          : _create
                          ? 'Crear bóveda cifrada'
                          : 'Desbloquear bóveda',
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (_attempts.cooldownSeconds > 0)
                    Text(
                      'Demasiados intentos. Esperá ${_attempts.cooldownSeconds} segundos.',
                    ),
                  TextButton.icon(
                    onPressed:
                        _busy || _path == null || _attempts.cooldownSeconds > 0
                        ? null
                        : _restore,
                    icon: const Icon(Icons.restore),
                    label: const Text('Restaurar copia cifrada'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
