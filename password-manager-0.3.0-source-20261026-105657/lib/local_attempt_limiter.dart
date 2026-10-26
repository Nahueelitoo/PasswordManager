import 'dart:async';

import 'package:flutter/foundation.dart';

/// Local UI throttle only. Restarting the process resets it; it does not limit
/// guesses against a copied encrypted file.
class LocalAttemptLimiter extends ChangeNotifier {
  int _failures = 0;
  int cooldownSeconds = 0;
  Timer? _timer;

  void failure() {
    if (cooldownSeconds > 0) return;
    if (++_failures < 5) return;
    _failures = 0;
    cooldownSeconds = 30;
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      cooldownSeconds--;
      if (cooldownSeconds == 0) timer.cancel();
      notifyListeners();
    });
    notifyListeners();
  }

  void success() {
    _failures = 0;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
