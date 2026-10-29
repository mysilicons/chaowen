import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rmrb_reader/core/engine_client.dart';
import 'package:rmrb_reader/state/providers.dart';
import 'package:rmrb_reader/views/reader_view.dart';

class FakeEngine extends EngineClient {
  FakeEngine({this.kind = 'normal'});

  final String kind;

  @override
  Future<Object?> call(
    String method, [
    Map<String, dynamic>? params,
    Duration timeout = const Duration(seconds: 30),
  ]) async {
    switch (method) {
      case 'issue.parse':
        return {
          'date': '2026-10-29',
          'pageCount': 3,
          'pages': [
            for (var no = 1; no <= 3; no++)
              {
                'no': no,
                'title': no == 1 ? '要闻' : '评论',
                'url': 'https://x/node_$no.html',
                'thumbUrl': 'https://x/t$no.jpg.2',
              },
          ],
        };
      case 'issue.status':
        return {'status': 'archived', 'mergedPath': 'D:/not/here.pdf', 'pageCount': 3};
      case 'article.page':
        return {
          'date': '2026-10-29',
          'pageNo': (params?['pageNo'] as int?) ?? 1,
          'title': '要闻',
          'kind': kind,
          'articles': [
            {
              'title': '更加清醒坚定地推进反腐败斗争',
              'author': '本报记者  张  洋',
              'url': 'https://x/c1.html',
              'blocks': [
                {'type': 'p', 'text': '在纪念中国工农红军长征胜利90周年大会上。'},
                {'type': 'p', 'text': '腐败是党和国家事业发展进程中的拦路虎。'},
              ],
            },
            {
              'title': '做伟大长征精神的传承者弘扬者践行者',
              'url': 'https://x/c2.html',
              'blocks': [
                {'type': 'p', 'text': '第二篇正文。'},
              ],
            },
          ],
        };
      default:
        return {};
    }
  }
}

/// 让阅读器一进来就有目标版面
class OpenTarget extends ReaderTarget {
  @override
  ({String date, int no})? build() => (date: '2026-10-29', no: 1);
}

Widget wrap(Widget child, EngineClient engine) => ProviderScope(
  overrides: [
    engineProvider.overrideWithValue(engine),
    readerTargetProvider.overrideWith(OpenTarget.new),
  ],
  child: MaterialApp(home: Scaffold(body: child)),
);

void main() {
  Future<void> pumpReader(WidgetTester tester, FakeEngine engine) async {
    tester.view.physicalSize = const Size(1400, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(wrap(const ReaderView(), engine));
    await tester.pumpAndSettle();
  }

  testWidgets('文字模式渲染标题、作者与段落', (tester) async {
    await pumpReader(tester, FakeEngine());

    expect(find.text('第01版 · 要闻'), findsOneWidget);
    expect(find.text('更加清醒坚定地推进反腐败斗争'), findsOneWidget);
    expect(find.text('本报记者  张  洋'), findsOneWidget);
    expect(find.textContaining('在纪念中国工农红军'), findsOneWidget);
  });

  testWidgets('版条可切换版面并保持版号', (tester) async {
    await pumpReader(tester, FakeEngine());

    await tester.tap(find.text('02').first);
    await tester.pumpAndSettle();

    expect(find.text('第02版 · 评论'), findsOneWidget);
    expect(find.text('第01版 · 要闻'), findsNothing);
  });

  testWidgets('一次只显示一篇，可切换下一篇', (tester) async {
    await pumpReader(tester, FakeEngine());

    expect(find.text('第 1 / 2 篇'), findsOneWidget);
    expect(find.text('做伟大长征精神的传承者弘扬者践行者'), findsNothing);

    await tester.tap(find.text('下一篇'));
    await tester.pumpAndSettle();

    expect(find.text('第 2 / 2 篇'), findsOneWidget);
    expect(find.text('做伟大长征精神的传承者弘扬者践行者'), findsOneWidget);
    expect(find.text('更加清醒坚定地推进反腐败斗争'), findsNothing);
  });

  testWidgets('纯图版显示降级提示', (tester) async {
    await pumpReader(tester, FakeEngine(kind: 'image_only'));

    expect(find.textContaining('本版以图片为主'), findsOneWidget);
    expect(find.text('看 PDF'), findsOneWidget);
  });

  testWidgets('未下载时 PDF 模式给出提示', (tester) async {
    await pumpReader(tester, FakeEngine());

    await tester.tap(find.text('PDF'));
    await tester.pumpAndSettle();

    // 未下载切换到 PDF：先弹窗询问是否下载
    expect(find.text('本期还没下载'), findsOneWidget);
    expect(find.text('下载本期'), findsOneWidget);
    expect(find.text('先看文字'), findsOneWidget);
  });
}
