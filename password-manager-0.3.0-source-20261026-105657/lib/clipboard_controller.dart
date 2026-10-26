import 'dart:async';

import 'package:flutter/services.dart';

class ClipboardController {
  Timer? _timer;
  bool _disposed = false;
  int _generation = 0;
  String? _lastCopied;
  Future<void> _pending = Future.value();

  Future<void> _enqueue(Future<void> Function() action) {
    final operation = _pending.then((_) => action());
    _pending = operation.catchError((Object _) {});
    return operation;
  }

  Future<void> copy(String value) {
    if (_disposed) return Future.value();
    final generation = ++_generation;
    _timer?.cancel();
    return _enqueue(() async {
      if (_disposed || generation != _generation) return;
      await Clipboard.setData(ClipboardData(text: value));
      _lastCopied = value;
      if (_disposed || generation != _generation) {
        await _clear();
        return;
      }
      _timer = Timer(
        const Duration(seconds: 30),
        () => unawaited(clearOwned()),
      );
    });
  }

  Future<void> _clear() async {
    final value = _lastCopied;
    _lastCopied = null;
    if (value == null) return;
    try {
      final current = await Clipboard.getData(Clipboard.kTextPlain);
      if (current?.text == value) {
        await Clipboard.setData(const ClipboardData(text: ''));
      }
    } on PlatformException {
      // Best effort. Does not remove clipboard history or other apps' copies.
    } on MissingPluginException {
      // The platform runner may already be shutting down.
    }
  }

  Future<void> clearOwned() {
    _timer?.cancel();
    ++_generation;
    return _enqueue(_clear);
  }

  void dispose() {
    _disposed = true;
    unawaited(clearOwned());
  }
}
