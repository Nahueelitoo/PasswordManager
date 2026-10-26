import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:password_manager/security_dialog.dart';
import 'package:password_manager/restore_dialog.dart';
import 'package:password_manager/account_entry.dart';
import 'package:password_manager/account_history_dialog.dart';
import 'package:password_manager/clipboard_controller.dart';
import 'package:flutter/services.dart';

void main() {
  testWidgets(
    'Credential dialog validates confirmation and supports a PIN-only change',
    (tester) async {
      SecurityChange? saved;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SecurityDialog(
              onSave: (change) async {
                saved = change;
                return false;
              },
            ),
          ),
        ),
      );
      await tester.enterText(
        find.byType(TextFormField).at(0),
        'frase actual ficticia de prueba',
      );
      await tester.enterText(find.byType(TextFormField).at(3), '87654321');
      await tester.ensureVisible(find.text('Guardar y bloquear'));
      await tester.tap(find.text('Guardar y bloquear'));
      await tester.pump();
      expect(find.text('Los PIN no coinciden'), findsOneWidget);
      expect(saved, isNull);
      await tester.enterText(find.byType(TextFormField).at(4), '87654321');
      await tester.tap(find.text('Guardar y bloquear'));
      await tester.pump();
      expect(saved!.newMaster, isNull);
      expect(saved!.newPin, '87654321');
      expect(saved!.currentMaster, 'frase actual ficticia de prueba');
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'Restore requires confirmation and shows validation failure without discarding input',
    (tester) async {
      var attempts = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RestoreDialog(
              onRestore: (_) async {
                attempts++;
                throw StateError('fictitious');
              },
            ),
          ),
        ),
      );
      await tester.enterText(
        find.byType(TextField),
        'frase ficticia de la copia',
      );
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pump();
      await tester.tap(find.text('Validar y restaurar'));
      await tester.pump();
      expect(attempts, 1);
      expect(find.textContaining('No se pudo restaurar.'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'frase ficticia de la copia',
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'History masks passwords and copies an explicitly selected previous password',
    (tester) async {
      String? copied;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.setData') {
              copied = (call.arguments as Map)['text'] as String;
              return null;
            }
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null),
      );
      final clipboard = ClipboardController();
      final old = AccountEntry(
        'Servicio',
        'usuario',
        'anterior ficticia',
        '',
        '',
        id: 'one',
      );
      final entry = AccountEntry(
        'Servicio',
        'usuario',
        'nueva ficticia',
        '',
        '',
        id: 'one',
      ).withPrevious(old);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AccountHistoryDialog(entry: entry, clipboard: clipboard),
          ),
        ),
      );
      expect(find.text('anterior ficticia'), findsNothing);
      await tester.tap(find.byTooltip('Copiar contraseña anterior'));
      await tester.pump();
      expect(copied, 'anterior ficticia');
      await tester.tap(find.byTooltip('Mostrar contraseña anterior'));
      await tester.pump();
      expect(find.text('anterior ficticia'), findsOneWidget);
      clipboard.dispose();
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
    },
  );
}
