import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rmrb_reader/core/engine_client.dart';
import 'package:rmrb_reader/state/providers.dart';
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
  child: MaterialApp(home: Scaffold(body: child)),
);

void main() {
  testWidgets('下载中心展示低速策略与空队列', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(wrap(const DownloadsView(), FakeEngine()));
    await tester.pumpAndSettle();

    expect(find.text('下载中心'), findsOneWidget);
    expect(find.textContaining('1 并发 · 1 秒间隔'), findsOneWidget);
    expect(find.text('暂无任务'), findsOneWidget);
    expect(find.text('开始下载'), findsOneWidget);
  });
}
