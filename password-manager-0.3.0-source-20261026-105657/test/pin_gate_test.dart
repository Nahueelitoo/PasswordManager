import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:password_manager/pin_gate.dart';

void main() {
  testWidgets('Cooldown persists across dialogs and expires after 30 seconds', (
    tester,
  ) async {
    final gate = DemoPinGate();
    gate.configure('12345678');
    for (var i = 0; i < 5; i++) {
      expect(gate.verify('00000000'), isFalse);
    }
    expect(gate.cooldownSeconds, 30);
    expect(gate.verify('12345678'), isFalse);
    await tester.pump(const Duration(seconds: 30));
    expect(gate.cooldownSeconds, 0);
    expect(gate.verify('12345678'), isTrue);
    gate.dispose();
    await tester.pumpWidget(const SizedBox());
  });
}
