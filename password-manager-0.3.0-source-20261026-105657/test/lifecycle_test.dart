import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:password_manager/main.dart';
import 'package:password_manager/vault_page.dart';
import 'package:password_manager/vault_store.dart';
import 'package:password_manager/account_entry.dart';
import 'package:password_manager/windows_services.dart';

import 'vault_page_test.dart' show waitFor;

class DelayedStore extends VaultStore {
  DelayedStore(super.path);
  final started = Completer<void>();
  final resume = Completer<void>();
  bool delayCreate = false, delaySave = false;
  @override
  Future<void> create(String master, String pin) async {
    if (delayCreate) {
      started.complete();
      await resume.future;
    }
    await super.create(master, pin);
  }

  @override
  Future<void> save(List<AccountEntry> entries) async {
    if (delaySave) {
      started.complete();
      await resume.future;
    }
    await super.save(entries);
  }
}

void main() {
  for (final native in [false, true]) {
    testWidgets(
      '${native ? 'Windows lock' : 'Hiding'} during creation clears fields and prevents deferred unlock',
      (tester) async {
        final dir = await tester.runAsync(
          () => Directory.systemTemp.createTemp('pm-open-lifecycle-'),
        );
        final store = DelayedStore('${dir!.path}/vault.kdbx')
          ..delayCreate = true;
        await tester.pumpWidget(
          MaterialApp(
            home: VaultPage(
              initialPath: store.path,
              storeFactory: (_) => store,
            ),
          ),
        );
        await tester.enterText(
          find.byType(TextFormField).at(0),
          'frase ficticia de ciclo de vida',
        );
        await tester.enterText(
          find.byType(TextFormField).at(1),
          'frase ficticia de ciclo de vida',
        );
        await tester.enterText(find.byType(TextFormField).at(2), '12345678');
        await tester.enterText(find.byType(TextFormField).at(3), '12345678');
        await tester.ensureVisible(find.text('Crear bóveda cifrada'));
        await tester.tap(find.text('Crear bóveda cifrada'));
        await tester.pump();
        expect(store.started.isCompleted, isTrue);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        if (native) {
          await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
            windowsServices.name,
            const StandardMethodCodec().encodeMethodCall(
              const MethodCall('lockSession'),
            ),
            (_) {},
          );
        } else {
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.hidden,
          );
        }
        await tester.pump();
        for (final field in tester.widgetList<TextFormField>(
          find.byType(TextFormField),
        )) {
          expect(field.controller!.text, isEmpty);
        }
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        store.resume.complete();
        await waitFor(
          tester,
          find.text('La bóveda quedó bloqueada al ocultar la aplicación.'),
        );
        expect(find.text('Tus cuentas'), findsNothing);
        expect(store.unlocked, isFalse);
        await tester.pumpWidget(const SizedBox());
        await tester.runAsync(() => dir.delete(recursive: true));
      },
    );

    testWidgets(
      '${native ? 'Windows lock' : 'Hiding'} during save dismisses secrets immediately and locks after save',
      (tester) async {
        final dir = await tester.runAsync(
          () => Directory.systemTemp.createTemp('pm-save-lifecycle-'),
        );
        final store = DelayedStore('${dir!.path}/vault.kdbx');
        await tester.runAsync(
          () => store.create('frase ficticia de ciclo de vida', '12345678'),
        );
        var locked = false;
        await tester.pumpWidget(
          MaterialApp(
            home: AccountsPage(
              store: store,
              onLock: () async {
                await store.lock();
                locked = true;
              },
            ),
          ),
        );
        await tester.tap(find.text('Agregar cuenta'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextFormField), '12345678');
        await tester.tap(find.text('Abrir cuenta'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byType(TextFormField).at(0),
          'Cuenta ficticia',
        );
        await tester.enterText(
          find.byType(TextFormField).at(2),
          'secreto ficticio de ciclo de vida',
        );
        store.delaySave = true;
        await tester.tap(find.text('Guardar cifrado'));
        await tester.pump();
        expect(store.started.isCompleted, isTrue);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        if (native) {
          await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
            windowsServices.name,
            const StandardMethodCodec().encodeMethodCall(
              const MethodCall('lockSession'),
            ),
            (_) {},
          );
        } else {
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.hidden,
          );
        }
        await tester.pump();
        expect(find.text('Bloqueando bóveda…'), findsOneWidget);
        expect(find.byType(TextFormField), findsNothing);
        expect(locked, isFalse);
        store.resume.complete();
        for (var i = 0; i < 200 && !locked; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 50)),
          );
          await tester.pump();
        }
        expect(locked, isTrue);
        expect(store.unlocked, isFalse);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pumpWidget(const SizedBox());
        await tester.runAsync(() => dir.delete(recursive: true));
      },
    );
  }
}
