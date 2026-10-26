import 'package:flutter/services.dart';

import 'dart:async';

const windowsServices = MethodChannel('password_manager/windows');
final _lockRequests = StreamController<void>.broadcast(sync: true);
bool _listening = false;

Stream<void> get windowsLockRequests {
  if (!_listening) {
    windowsServices.setMethodCallHandler((call) async {
      if (call.method == 'lockSession') {
        _lockRequests.add(null);
        return;
      }
      throw MissingPluginException();
    });
    _listening = true;
  }
  return _lockRequests.stream;
}

Future<String?> chooseBackupFile({bool save = false}) => windowsServices
    .invokeMethod<String>(save ? 'chooseExport' : 'chooseBackup');
