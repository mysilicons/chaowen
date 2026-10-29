import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rmrb_reader/core/engine_client.dart';
import 'package:rmrb_reader/state/providers.dart';
import 'package:rmrb_reader/theme/palette.dart';
import 'package:rmrb_reader/views/downloads_view.dart';

class FakeEngine extends EngineClient {
  @override
  Future<Object?> call(
    String method, [
    Map<String, dynamic>? params,
    Duration timeout = const Duration(seconds: 30),
  ]) async => {};
}

Widget wrap(Widget child, EngineClient engine) => ProviderScope(
  overrides: [engineProvider.overrideWithValue(engine)],
  child: MaterialApp(theme: buildTheme(Brightness.light), home: Scaffold(body: child)),
);

void main() {
  testWidgets('快捷区间按钮的文字使用主题深色', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(wrap(const DownloadsView(), FakeEngine()));
    await tester.pumpAndSettle();

    for (final label in ['近 7 天', '近 30 天', '本月', '本年']) {
      final widget = tester.widget<Text>(find.text(label));
      final color = widget.style?.color;
      expect(
        color,
        const Color(0xFF111111),
        reason: '$label 的文字色应为近黑色（#111111），实际是 $color',
      );
    }
  });

  testWidgets('快捷区间按钮的底色跟随主题', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(wrap(const DownloadsView(), FakeEngine()));
    await tester.pumpAndSettle();

    final chip = tester.widget<ActionChip>(find.byType(ActionChip).first);
    expect(chip.backgroundColor, AppPalette.light.surface);
  });
}
