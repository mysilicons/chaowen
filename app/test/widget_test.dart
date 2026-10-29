import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rmrb_reader/core/engine_client.dart';
import 'package:rmrb_reader/state/providers.dart';
import 'package:rmrb_reader/views/library_view.dart';
import 'package:rmrb_reader/widgets/page_thumb.dart';

/// 只实现 UI 需要的两个方法，不启动真实引擎。
class FakeEngine extends EngineClient {
  final List<String> calls = [];

  @override
  Future<Object?> call(
    String method, [
    Map<String, dynamic>? params,
    Duration timeout = const Duration(seconds: 30),
  ]) async {
    calls.add(method);
    if (method == 'issue.page') {
      final no = (params?['pageNo'] as int?) ?? 1;
      return {
        'no': no,
        'title': '要闻',
        'thumbUrl': 'https://x/lazy-$no.jpg.2',
        'pdfUrl': 'https://x/p$no.pdf',
      };
    }
    if (method == 'issue.parse') {
      return {
        'date': '2026-10-29',
        'pageCount': 20,
        'pages': [
          for (var no = 1; no <= 20; no++)
            {
              'no': no,
              'title': no == 5 ? '评论' : (no == 8 ? '广告' : '要闻'),
              'url': 'https://x/node_$no.html',
              'articles': [
                {'title': '第$no版文章一', 'url': 'https://x/c$no.html'},
              ],
            },
        ],
      };
    }
    if (method == 'library.month') {
      return [
        {'date': '2026-10-29', 'status': 'archived', 'bytes': 65780526, 'pageCount': 20},
      ];
    }
    return {};
  }
}

Widget wrap(Widget child, EngineClient engine) => ProviderScope(
  overrides: [engineProvider.overrideWithValue(engine)],
  child: MaterialApp(home: Scaffold(body: child)),
);

void main() {
  testWidgets('书架渲染 20 个版面与日期标题', (tester) async {
    tester.view.physicalSize = const Size(1600, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(wrap(const LibraryView(), FakeEngine()));
    await tester.pumpAndSettle();

    expect(find.textContaining('2026年10月29日'), findsOneWidget);
    expect(find.textContaining('20 版'), findsOneWidget);
    expect(find.byType(PageThumb), findsNWidgets(20));
  });

  testWidgets('缩略图缺失时按需补抓每一版', (tester) async {
    tester.view.physicalSize = const Size(1600, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final engine = FakeEngine();
    await tester.pumpWidget(wrap(const LibraryView(), engine));
    await tester.pumpAndSettle();

    // 假数据的 pages 都没有 thumbUrl，界面应逐版调用 issue.page
    final lazyCalls = engine.calls.where((c) => c == 'issue.page').length;
    expect(lazyCalls, greaterThan(5), reason: '可见的每一版都要补抓缩略图');
  });

  testWidgets('已归档日期显示已下载按钮', (tester) async {
    tester.view.physicalSize = const Size(1600, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(wrap(const LibraryView(), FakeEngine()));
    await tester.pumpAndSettle();

    expect(find.text('下载本期'), findsNothing);
  });

  testWidgets('点击版面进入阅读器（设置阅读目标）', (tester) async {
    tester.view.physicalSize = const Size(1600, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(wrap(const LibraryView(), FakeEngine()));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(PageThumb).first);
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(LibraryView)),
    );
    expect(container.read(readerTargetProvider)?.no, 1);
    expect(container.read(readerTargetProvider)?.date, '2026-10-29');
    expect(container.read(shellIndexProvider), 1);
  });
}
