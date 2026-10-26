import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:password_manager/main.dart';
import 'package:password_manager/account_view_dialog.dart';

Future<void> configurePin(WidgetTester tester) async {
  await tester.enterText(find.byType(TextFormField).at(0), '12345678');
  await tester.enterText(find.byType(TextFormField).at(1), '12345678');
  await tester.tap(find.text('Crear PIN y continuar'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'Generator defaults to letters and numbers and allows few symbols',
    (tester) async {
      await tester.pumpWidget(const PasswordManagerApp(demo: true));
      await tester.tap(find.text('Agregar cuenta'));
      await tester.pumpAndSettle();
      await configurePin(tester);
      final option = find.byType(CheckboxListTile);
      expect(tester.widget<CheckboxListTile>(option).value, isFalse);
      await tester.ensureVisible(find.text('Generar contraseña'));
      await tester.tap(find.text('Generar contraseña'));
      await tester.pump();
      String generated() => tester
          .widget<TextFormField>(find.byType(TextFormField).at(2))
          .controller!
          .text;
      expect(generated(), matches(RegExp(r'^[a-zA-Z0-9]{24}$')));
      await tester.ensureVisible(option);
      await tester.tap(option);
      await tester.pump();
      await tester.ensureVisible(find.text('Generar contraseña'));
      await tester.tap(find.text('Generar contraseña'));
      await tester.pump();
      expect(generated().length, 24);
      expect(
        RegExp('[^a-zA-Z0-9]').allMatches(generated()).length,
        inInclusiveRange(1, 2),
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('PIN gates account data on every opening and copy works', (
    tester,
  ) async {
    final clipboardCalls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          clipboardCalls.add(call);

          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );
    await tester.pumpWidget(const PasswordManagerApp(demo: true));
    expect(find.text('usuario@example.com'), findsNothing);
    await tester.tap(find.text('Correo de ejemplo'));
    await tester.pumpAndSettle();
    expect(find.text('Crear PIN de prueba'), findsOneWidget);
    expect(find.text('usuario@example.com'), findsNothing);
    await configurePin(tester);
    expect(find.text('usuario@example.com'), findsOneWidget);
    expect(find.byType(AccountViewDialog), findsOneWidget);
    final fields = find.descendant(
      of: find.byType(AccountViewDialog),
      matching: find.byType(TextField),
    );
    expect(fields, findsNWidgets(3));
    expect(
      tester.widgetList<TextField>(fields).every((field) => field.readOnly),
      isTrue,
    );
    expect(tester.widget<TextField>(fields.last).obscureText, isTrue);
    expect(find.text('Generar contraseña'), findsNothing);
    expect(find.byType(Slider), findsNothing);
    expect(find.text('Red / dirección web (opcional)'), findsNothing);
    expect(find.byTooltip('Mostrar contraseña'), findsNothing);
    await tester.tap(find.byTooltip('Copiar usuario'));
    await tester.pumpAndSettle();
    expect(
      clipboardCalls
          .where((call) => call.method == 'Clipboard.setData')
          .last
          .arguments,
      {'text': 'usuario@example.com'},
    );
    await tester.tap(find.byTooltip('Copiar contraseña'));
    await tester.pumpAndSettle();
    expect(
      clipboardCalls
          .where((call) => call.method == 'Clipboard.setData')
          .last
          .arguments,
      {'text': 'Solo-un-ejemplo-123!'},
    );
    await tester.tap(find.text('Cerrar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Correo de ejemplo'));
    await tester.pumpAndSettle();
    expect(find.text('Ingresá tu PIN'), findsOneWidget);
    expect(find.text('usuario@example.com'), findsNothing);
    await tester.enterText(find.byType(TextFormField), '87654321');
    await tester.tap(find.text('Abrir cuenta'));
    await tester.pumpAndSettle();
    expect(find.text('PIN incorrecto'), findsOneWidget);
    expect(find.text('usuario@example.com'), findsNothing);
    await tester.enterText(find.byType(TextFormField), '12345678');
    await tester.tap(find.text('Abrir cuenta'));
    await tester.pumpAndSettle();
    expect(find.text('usuario@example.com'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Edit and delete have separate PIN-protected controls', (
    tester,
  ) async {
    await tester.pumpWidget(const PasswordManagerApp(demo: true));
    expect(find.text('LOCAL'), findsNothing);
    expect(find.text('Editar'), findsNothing);
    expect(
      find.descendant(
        of: find.byTooltip('Editar cuenta'),
        matching: find.byIcon(Icons.edit),
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining('Páginas, aplicaciones y servicios'),
      findsNothing,
    );
    await tester.tap(find.byTooltip('Editar cuenta'));
    await tester.pumpAndSettle();
    await configurePin(tester);
    expect(find.text('Editar cuenta'), findsOneWidget);
    expect(find.byType(AccountViewDialog), findsNothing);
    await tester.enterText(
      find.byType(TextFormField).at(1),
      'nuevo@example.org',
    );
    await tester.tap(find.text('Guardar en prueba'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Correo de ejemplo'));
    await tester.pumpAndSettle();
    expect(find.text('Ingresá tu PIN'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField), '12345678');
    await tester.tap(find.text('Abrir cuenta'));
    await tester.pumpAndSettle();
    expect(find.text('nuevo@example.org'), findsOneWidget);
    await tester.tap(find.text('Cerrar'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Eliminar cuenta'));
    await tester.pumpAndSettle();
    expect(find.text('Ingresá tu PIN'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField), '12345678');
    await tester.tap(find.text('Abrir cuenta'));
    await tester.pumpAndSettle();
    expect(find.text('Eliminar cuenta'), findsOneWidget);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(find.text('Correo de ejemplo'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('PIN requires eight digits and matching confirmation', (
    tester,
  ) async {
    await tester.pumpWidget(const PasswordManagerApp(demo: true));
    await tester.tap(find.text('Agregar cuenta'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), '12ab');
    await tester.tap(find.text('Crear PIN y continuar'));
    await tester.pumpAndSettle();
    expect(find.text('Ingresá exactamente 8 dígitos'), findsWidgets);
    await tester.enterText(find.byType(TextFormField).at(0), '12345678');
    await tester.enterText(find.byType(TextFormField).at(1), '87654321');
    await tester.tap(find.text('Crear PIN y continuar'));
    await tester.pumpAndSettle();
    expect(find.text('Los PIN no coinciden'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Create a demo account then search by service only', (
    tester,
  ) async {
    await tester.pumpWidget(const PasswordManagerApp(demo: true));
    await tester.tap(find.text('Agregar cuenta'));
    await tester.pumpAndSettle();
    await configurePin(tester);
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'Servicio ficticio');
    await tester.enterText(fields.at(1), 'prueba@example.org');
    await tester.enterText(fields.at(2), 'Una-clave-ficticia-123');
    await tester.tap(find.text('Guardar en prueba'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(ListTile, 'Servicio ficticio'), findsOneWidget);
    expect(find.text('prueba@example.org'), findsNothing);
    await tester.enterText(find.byType(TextField).first, 'Servicio ficticio');
    await tester.pumpAndSettle();
    expect(find.widgetWithText(ListTile, 'Servicio ficticio'), findsOneWidget);
    expect(find.text('Correo de ejemplo'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
