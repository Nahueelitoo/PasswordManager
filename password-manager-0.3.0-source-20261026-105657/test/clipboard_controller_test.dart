import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:password_manager/clipboard_controller.dart';

void main() {
  testWidgets(
    'Clipboard clears its copies and preserves unrelated later copies',
    (tester) async {
      String? contents;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.setData') {
              contents = (call.arguments as Map)['text'] as String;
            }
            if (call.method == 'Clipboard.getData') return {'text': contents};
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null),
      );
      final clipboard = ClipboardController();
      await clipboard.copy('ficticio');
      await tester.pump(const Duration(seconds: 30));
      expect(contents, '');
      await clipboard.copy('ficticio');
      contents = 'copiado desde otra aplicación';
      await tester.pump(const Duration(seconds: 30));
      expect(contents, 'copiado desde otra aplicación');
      clipboard.dispose();
      await tester.pump();
    },
  );

  testWidgets('Disposal during a pending copy clears the completed copy', (
    tester,
  ) async {
    final completed = Completer<void>();
    String? contents;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            final text = (call.arguments as Map)['text'] as String;
            if (text.isNotEmpty) await completed.future;
            contents = text;
          }
          if (call.method == 'Clipboard.getData') return {'text': contents};
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );
    final clipboard = ClipboardController();
    final copy = clipboard.copy('ficticio');
    await tester.pump();
    clipboard.dispose();
    completed.complete();
    await copy;
    await tester.pump();
    expect(contents, '');
  });
}
