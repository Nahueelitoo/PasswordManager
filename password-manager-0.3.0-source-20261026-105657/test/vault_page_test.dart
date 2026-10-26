import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:password_manager/vault_page.dart';

Future<void> waitFor(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 200; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
    if (finder.evaluate().isNotEmpty) {
      await tester.pump(const Duration(milliseconds: 300));
      return;
    }
  }
  fail('La operación no terminó dentro del tiempo esperado.');
}

void main() {
  testWidgets(
    'Create, save, lock with an open entry, unlock and verify persisted PIN',
    (tester) async {
      final directory = await tester.runAsync(
        () => Directory.systemTemp.createTemp('pm-ui-vault-'),
      );
      final path = '${directory!.path}/vault.kdbx';
      await tester.pumpWidget(MaterialApp(home: VaultPage(initialPath: path)));
      expect(find.textContaining('Archivo local (.kdbx)'), findsNothing);
      expect(find.text(path), findsNothing);
      expect(find.byType(TextFormField), findsNWidgets(4));
      await tester.enterText(
        find.byType(TextFormField).at(0),
        'frase ficticia para prueba de interfaz',
      );
      await tester.enterText(
        find.byType(TextFormField).at(1),
        'frase ficticia para prueba de interfaz',
      );
      await tester.enterText(find.byType(TextFormField).at(2), '12345678');
      await tester.enterText(find.byType(TextFormField).at(3), '12345678');
      await tester.ensureVisible(find.text('Crear bóveda cifrada'));
      await tester.tap(find.text('Crear bóveda cifrada'));
      await waitFor(tester, find.text('Tus cuentas'));
      await tester.tap(find.text('Agregar cuenta'));
      await tester.pumpAndSettle();
      expect(find.text('Ingresá tu PIN'), findsOneWidget);
      await tester.enterText(find.byType(TextFormField), '12345678');
      await tester.tap(find.text('Abrir cuenta'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextFormField).at(0),
        'Cuenta persistente',
      );
      await tester.enterText(
        find.byType(TextFormField).at(1),
        'prueba@example.net',
      );
      await tester.enterText(
        find.byType(TextFormField).at(2),
        'contraseña ficticia de cuenta',
      );
      await tester.tap(find.text('Guardar cifrado'));
      await waitFor(
        tester,
        find.widgetWithText(ListTile, 'Cuenta persistente'),
      );
      await tester.tap(find.byTooltip('Bloquear bóveda'));
      await waitFor(tester, find.text('Desbloquear bóveda'));
      expect(find.text('Cuenta persistente'), findsNothing);
      await tester.enterText(
        find.byType(TextFormField).at(0),
        'frase ficticia para prueba de interfaz',
      );
      await tester.tap(find.text('Desbloquear bóveda'));
      await waitFor(tester, find.text('Tus cuentas'));
      expect(find.text('Cuenta persistente'), findsOneWidget);
      await tester.tap(find.text('Cuenta persistente'));
      await tester.pumpAndSettle();
      expect(find.text('Ingresá tu PIN'), findsOneWidget);
      expect(find.text('prueba@example.net'), findsNothing);
      await tester.enterText(find.byType(TextFormField), '12345678');
      await tester.tap(find.text('Abrir cuenta'));
      await tester.pumpAndSettle();
      expect(find.text('prueba@example.net'), findsOneWidget);
      // Inactivity must dismiss the sensitive dialog as well as the account list.
      await tester.pump(const Duration(minutes: 5));
      await waitFor(tester, find.text('Desbloquear bóveda'));
      expect(find.text('prueba@example.net'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() => directory.delete(recursive: true));
    },
  );
}
