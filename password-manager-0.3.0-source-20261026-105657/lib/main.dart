import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';

import 'account_entry.dart';
import 'clipboard_controller.dart';
import 'password_generator.dart';
import 'pin_gate.dart';
import 'vault_page.dart';
import 'vault_store.dart';
import 'windows_services.dart';
import 'security_dialog.dart';
import 'account_history_dialog.dart';
import 'input_validation.dart';
import 'account_view_dialog.dart';

void main() => runApp(const PasswordManagerApp());

class PasswordManagerApp extends StatelessWidget {
  const PasswordManagerApp({super.key, this.demo = false});
  final bool demo;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Password Manager',
    debugShowCheckedModeBanner: false,
    builder: (context, child) => demo
        ? Banner(
            message: 'DEMO',
            location: BannerLocation.topStart,
            child: child!,
          )
        : child!,
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xff496b58),
        brightness: Brightness.dark,
      ),
      useMaterial3: true,
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
      ),
    ),
    home: demo ? const AccountsPage() : const VaultPage(),
  );
}

class AccountsPage extends StatefulWidget {
  const AccountsPage({super.key, this.store, this.onLock});
  final VaultStore? store;
  final Future<void> Function()? onLock;
  @override
  State<AccountsPage> createState() => _AccountsPageState();
}

class _AccountsPageState extends State<AccountsPage>
    with WidgetsBindingObserver {
  final _pinGate = DemoPinGate();
  final _clipboard = ClipboardController();
  late final List<AccountEntry> _entries = widget.store == null
      ? [
          AccountEntry(
            'Correo de ejemplo',
            'usuario@example.com',
            'Solo-un-ejemplo-123!',
            'https://example.com',
            'Cuenta ficticia.',
          ),
        ]
      : List.of(widget.store!.entries);
  String _query = '';
  Timer? _idle;
  bool _saving = false;
  bool _lockPending = false;
  bool _locking = false;
  StreamSubscription<void>? _windowsLocks;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _windowsLocks = windowsLockRequests.listen((_) => unawaited(_lock()));
    GestureBinding.instance.pointerRouter.addGlobalRoute(_pointerActivity);
    HardwareKeyboard.instance.addHandler(_keyboardActivity);
    final pin = widget.store?.pin;
    if (pin != null) _pinGate.configure(pin);
    _touch();
  }

  void _touch() {
    if (widget.store == null || _locking) return;
    _idle?.cancel();
    _idle = Timer(const Duration(minutes: 5), _lock);
  }

  void _pointerActivity(PointerEvent event) {
    if (event is PointerDownEvent ||
        event is PointerMoveEvent ||
        event is PointerSignalEvent) {
      _touch();
    }
  }

  bool _keyboardActivity(KeyEvent event) {
    _touch();
    return false;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused) {
      _lock();
    }
  }

  Future<void> _lock() async {
    if (widget.onLock == null || _locking) return;
    setState(() => _locking = true);
    _idle?.cancel();
    Navigator.of(context).popUntil((route) => route.isFirst);
    unawaited(_clipboard.clearOwned());
    if (_saving) {
      _lockPending = true;
      return;
    }
    await _finishLock();
  }

  Future<void> _finishLock() async {
    _lockPending = false;
    await widget.onLock!();
  }

  Future<bool> _commit(
    List<AccountEntry> entries, {
    Future<void> Function()? task,
  }) async {
    setState(() => _saving = true);
    try {
      if (task != null) {
        await task();
      } else {
        await widget.store?.save(entries);
      }
      if (!mounted) return false;
      setState(() {
        _entries
          ..clear()
          ..addAll(widget.store?.entries ?? entries);
      });
      return true;
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error is VaultException ? error.message : 'No se pudo completar la operación. Revisá permisos, espacio o si el archivo cambió fuera de la aplicación.',
            ),
          ),
        );
      }
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
      if (_lockPending && mounted) await _finishLock();
    }
  }

  Future<void> _security() async {
    if (_saving || _locking || widget.store == null) return;
    final changed = await showDialog<bool>(
      animationStyle: AnimationStyle.noAnimation,
      context: context,
      barrierDismissible: false,
      builder: (_) => SecurityDialog(
        onSave: (change) {
          if (_locking || !mounted) return Future.value(false);
          return _commit(
            _entries,
            task: () => widget.store!.changeCredentials(
              currentMaster: change.currentMaster,
              newMaster: change.newMaster,
              newPin: change.newPin,
            ),
          );
        },
      ),
    );
    if (changed == true && mounted && !_locking) await _lock();
  }

  Future<void> _backup() async {
    if (_saving || _locking || widget.store == null) return;
    try {
      final destination = await chooseBackupFile(save: true);
      if (destination == null || !mounted || _locking || _saving) return;
      final saved = await _commit(
        _entries,
        task: () => widget.store!.exportBackup(destination),
      );
      if (saved && mounted && !_locking) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Copia cifrada creada y verificada. Conservá su contraseña maestra.',
            ),
          ),
        );
      }
    } catch (_) {
      if (mounted && !_locking) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No se pudo elegir el destino de la copia.'),
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _windowsLocks?.cancel();
    _idle?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_pointerActivity);
    HardwareKeyboard.instance.removeHandler(_keyboardActivity);
    _entries.clear();
    _pinGate.dispose();
    _clipboard.dispose();
    super.dispose();
  }

  Future<bool> _authorize() async =>
      await showDialog<bool>(
        animationStyle: AnimationStyle.noAnimation,
        context: context,
        barrierDismissible: false,
        builder: (_) => PinDialog(gate: _pinGate),
      ) ==
      true;

  Future<void> _edit([AccountEntry? original]) async {
    if (_saving || _locking || !await _authorize() || !mounted || _locking) {
      return;
    }
    await showDialog<AccountEntry>(
      animationStyle: AnimationStyle.noAnimation,
      context: context,
      builder: (_) => EntryDialog(
        entry: original,
        clipboard: _clipboard,
        persistent: widget.store != null,
        onSave: (result) async {
          if (_locking || !mounted) return false;
          final updated = List<AccountEntry>.of(_entries);
          if (original == null) {
            updated.add(result);
          } else {
            updated[updated.indexOf(original)] = result;
          }
          return _commit(updated);
        },
      ),
    );
  }

  Future<void> _view(AccountEntry entry) async {
    if (_saving || _locking || !await _authorize() || !mounted || _locking) {
      return;
    }
    await showDialog<void>(
      animationStyle: AnimationStyle.noAnimation,
      context: context,
      builder: (_) => AccountViewDialog(entry: entry, clipboard: _clipboard),
    );
  }

  Future<void> _delete(AccountEntry entry) async {
    if (_saving || _locking || !await _authorize() || !mounted || _locking) {
      return;
    }
    final confirmed = await showDialog<bool>(
      animationStyle: AnimationStyle.noAnimation,
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar cuenta'),
        content: Text('¿Eliminar “${entry.name}”?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (mounted && confirmed == true && !_locking) {
      await _commit(_entries.where((item) => item.id != entry.id).toList());
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_locking) {
      return const Scaffold(body: Center(child: Text('Bloqueando bóveda…')));
    }
    final filtered = _entries
        .where((e) => e.name.toLowerCase().contains(_query.toLowerCase()))
        .toList();
    return Listener(
      onPointerDown: (_) => _touch(),
      onPointerSignal: (_) => _touch(),
      child: Focus(
        onKeyEvent: (_, _) {
          _touch();
          return KeyEventResult.ignored;
        },
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Password Manager'),
            centerTitle: true,
            actions: [
              if (widget.store != null)
                PopupMenuButton<String>(
                  enabled: !_saving,
                  tooltip: 'Seguridad y copias',
                  onSelected: (value) {
                    if (value == 'security') _security();
                    if (value == 'backup') _backup();
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: 'security',
                      child: Text('Cambiar contraseña maestra o PIN'),
                    ),
                    PopupMenuItem(
                      value: 'backup',
                      child: Text('Guardar copia cifrada'),
                    ),
                  ],
                ),
              if (widget.onLock != null)
                IconButton(
                  onPressed: _saving ? null : _lock,
                  tooltip: 'Bloquear bóveda',
                  icon: const Icon(Icons.lock_outline),
                ),
            ],
          ),
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1000),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Tus cuentas',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 24),
                    TextField(
                      onChanged: (value) => setState(() => _query = value),
                      decoration: const InputDecoration(
                        labelText: 'Buscar por servicio',
                        prefixIcon: Icon(Icons.search),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: filtered.isEmpty
                          ? const Center(
                              child: Text('No hay cuentas que coincidan.'),
                            )
                          : ListView.builder(
                              itemCount: filtered.length,
                              itemBuilder: (context, index) {
                                final entry = filtered[index];
                                return Card(
                                  child: ListTile(
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 8,
                                    ),
                                    leading: const CircleAvatar(
                                      child: Icon(Icons.key),
                                    ),
                                    title: Text(entry.name),
                                    subtitle: const Text(
                                      'Datos protegidos con PIN',
                                    ),
                                    onTap: _saving ? null : () => _view(entry),
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton.filledTonal(
                                          tooltip: 'Editar cuenta',
                                          style: IconButton.styleFrom(
                                            shape: const CircleBorder(),
                                            fixedSize: const Size(44, 44),
                                          ),
                                          onPressed: _saving
                                              ? null
                                              : () => _edit(entry),
                                          icon: const Icon(
                                            Icons.edit,
                                            size: 22,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        IconButton(
                                          tooltip: 'Eliminar cuenta',
                                          onPressed: _saving
                                              ? null
                                              : () => _delete(entry),
                                          icon: const Icon(
                                            Icons.delete_outline,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton.icon(
                        onPressed: _saving ? null : _edit,
                        icon: const Icon(Icons.add),
                        label: Text(_saving ? 'Guardando…' : 'Agregar cuenta'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class EntryDialog extends StatefulWidget {
  const EntryDialog({
    super.key,
    this.entry,
    required this.clipboard,
    this.persistent = false,
    this.onSave,
  });
  final AccountEntry? entry;
  final bool persistent;
  final ClipboardController clipboard;
  final Future<bool> Function(AccountEntry)? onSave;
  @override
  State<EntryDialog> createState() => _EntryDialogState();
}

class _EntryDialogState extends State<EntryDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.entry?.name);
  late final _username = TextEditingController(text: widget.entry?.username);
  late final _password = TextEditingController(text: widget.entry?.password);
  late final _url = TextEditingController(text: widget.entry?.url);
  late final _notes = TextEditingController(text: widget.entry?.notes);
  bool _visible = false, _symbols = false;
  int _length = 24;
  bool _busy = false;
  String? _saveError;

  Future<void> _save() async {
    if (_busy || !_formKey.currentState!.validate()) return;
    final entry = AccountEntry(
      _name.text.trim(),
      _username.text.trim(),
      _password.text,
      _url.text.trim(),
      _notes.text,
      id: widget.entry?.id,
    );
    setState(() {
      _busy = true;
      _saveError = null;
    });
    final saved = await widget.onSave?.call(entry) ?? true;
    if (!mounted) return;
    if (saved) {
      Navigator.pop(context, entry);
    } else {
      setState(() {
        _busy = false;
        _saveError = 'No se pudo guardar. Tus cambios siguen en este formulario; podés reintentar o cancelar.';
      });
    }
  }

  Widget _copyButton(
    TextEditingController controller,
    String label,
  ) => IconButton(
    tooltip: 'Copiar $label',
    icon: const Icon(Icons.copy_outlined),
    onPressed: () async {
      if (controller.text.isEmpty) return;
      try {
        await widget.clipboard.copy(controller.text);
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
    },
  );

  @override
  void dispose() {
    for (final c in [_name, _username, _password, _url, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.entry == null ? 'Agregar cuenta' : 'Editar cuenta'),
    content: AbsorbPointer(
      absorbing: _busy,
      child: SizedBox(
        width: 500,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_saveError != null)
                  Text(
                    _saveError!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                Text(
                  widget.persistent
                      ? 'Guardado cifrado al confirmar · Copia anterior automática'
                      : 'Solo datos ficticios · Sin almacenamiento permanente',
                ),
                const SizedBox(height: 20),
                TextFormField(
                  controller: _name,
                  decoration: const InputDecoration(
                    labelText: 'Nombre del servicio',
                  ),
                  validator: (v) => InputValidation.bounded(
                    v,
                    'el nombre del servicio',
                    InputValidation.maxNameLength,
                    required: true,
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _username,
                  validator: (v) => InputValidation.bounded(
                    v,
                    'El usuario',
                    InputValidation.maxUsernameLength,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Usuario o correo electrónico',
                    suffixIcon: _copyButton(_username, 'usuario'),
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _password,
                  obscureText: !_visible,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(
                    labelText: 'Contraseña',
                    suffixIcon: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _copyButton(_password, 'contraseña'),
                        IconButton(
                          tooltip: _visible
                              ? 'Ocultar contraseña'
                              : 'Mostrar contraseña',
                          onPressed: () => setState(() => _visible = !_visible),
                          icon: Icon(
                            _visible ? Icons.visibility_off : Icons.visibility,
                          ),
                        ),
                      ],
                    ),
                  ),
                  validator: InputValidation.password,
                ),
                const SizedBox(height: 16),
                Text('Longitud: $_length caracteres'),
                Slider(
                  value: _length.toDouble(),
                  min: 20,
                  max: 30,
                  divisions: 10,
                  label: '$_length',
                  onChanged: (v) => setState(() => _length = v.round()),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Incluir símbolos (1 o 2)'),
                  subtitle: const Text(
                    'Desactivado: solo letras y números. Se aplica al generar.',
                  ),
                  value: _symbols,
                  onChanged: (v) => setState(() => _symbols = v ?? false),
                ),
                OutlinedButton.icon(
                  onPressed: () => _password.text = generatePassword(
                    length: _length,
                    symbols: _symbols,
                  ),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Generar contraseña'),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _url,
                  validator: (v) => InputValidation.bounded(
                    v,
                    'La dirección',
                    InputValidation.maxUrlLength,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Red / dirección web (opcional)',
                    suffixIcon: _copyButton(_url, 'dirección web'),
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _notes,
                  validator: (v) => InputValidation.bounded(
                    v,
                    'Las notas',
                    InputValidation.maxNotesLength,
                  ),
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Notas (opcional)',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
    actions: [
      if (widget.entry?.history.isNotEmpty ?? false)
        TextButton(
          onPressed: _busy
              ? null
              : () => showDialog<void>(
                  animationStyle: AnimationStyle.noAnimation,
                  context: context,
                  builder: (_) => AccountHistoryDialog(
                    entry: widget.entry!,
                    clipboard: widget.clipboard,
                  ),
                ),
          child: Text('Historial (${widget.entry!.history.length})'),
        ),
      TextButton(
        onPressed: _busy ? null : () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      FilledButton(
        onPressed: _busy ? null : _save,
        child: Text(
          _busy
              ? 'Guardando…'
              : widget.persistent
              ? 'Guardar cifrado'
              : 'Guardar en prueba',
        ),
      ),
    ],
  );
}
