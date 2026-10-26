import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:password_manager/local_attempt_limiter.dart';
import 'package:password_manager/vault_page.dart';
import 'package:password_manager/vault_store.dart';

class RejectingStore extends VaultStore {
  RejectingStore(super.path);
  static int calls = 0;
  @override
  Future<void> open(String master) async {
    calls++;
    throw const VaultException(
      'No se pudo abrir: contraseña incorrecta o archivo dañado.',
    );
  }
}

void main() {
  testWidgets(
    'Five local failures trigger a thirty-second cooldown and success resets failures',
    (tester) async {
      final limiter = LocalAttemptLimiter();
      for (var i = 0; i < 4; i++) {
        limiter.failure();
      }
      limiter.success();
      limiter.failure();
      expect(limiter.cooldownSeconds, 0);
      for (var i = 0; i < 4; i++) {
        limiter.failure();
      }
      expect(limiter.cooldownSeconds, 30);
      await tester.pump(const Duration(seconds: 30));
      expect(limiter.cooldownSeconds, 0);
      limiter.dispose();
    },
  );

  testWidgets('Master-password UI blocks further attempts during cooldown', (
    tester,
  ) async {
    RejectingStore.calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: VaultPage(
          initialPath: 'C:/fictitious-vault-for-throttle-test.kdbx',
          storeFactory: RejectingStore.new,
        ),
      ),
    );
    await tester.tap(find.text('Abrir bóveda'));
    await tester.pump();
    await tester.enterText(
      find.byType(TextFormField),
      'contraseña ficticia incorrecta',
    );
    for (var i = 0; i < 5; i++) {
      await tester.ensureVisible(find.text('Desbloquear bóveda'));
      await tester.tap(find.text('Desbloquear bóveda'));
      await tester.pump();
    }
    expect(RejectingStore.calls, 5);
    expect(
      find.text('Demasiados intentos. Esperá 30 segundos.'),
      findsOneWidget,
    );
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    await tester.pump(const Duration(seconds: 30));
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNotNull,
    );
    await tester.pumpWidget(const SizedBox());
  });
}
