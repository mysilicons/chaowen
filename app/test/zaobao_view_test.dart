import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rmrb_reader/core/engine_client.dart';
import 'package:rmrb_reader/core/models.dart';
import 'package:rmrb_reader/core/zaobao_client.dart';
import 'package:rmrb_reader/state/providers.dart';
import 'package:rmrb_reader/views/zaobao_view.dart';
import 'package:rmrb_reader/theme/palette.dart';

class NewsEngine extends EngineClient {
  NewsEngine({
    this.cached = true,
    this.preview = false,
    this.failRefresh = false,
    this.paged = false,
    this.extraItems = 0,
  });
  final bool cached;
  final bool preview;
  final bool failRefresh;
  final bool paged;
  final int extraItems;
  bool loadedOlder = false;
  final calls = <String>[];
  bool fetched = false;
  Completer<Object?>? delayedArticle;

  @override
  Future<Object?> call(
    String method, [
    Map<String, dynamic>? params,
    Duration timeout = const Duration(seconds: 30),
  ]) async {
    calls.add(method);
    switch (method) {
      case 'hello':
        return {
          'features': {'zaobaoReaderV1': true},
        };
      case 'zaobao.feed.get':
        final items = <Map<String, dynamic>>[
          {
            'articleId': '123',
            'title': '测试中国新闻',
            'url': 'https://www.zaobao.com/news/china/story20261030-123',
            'read': false,
          },
          {
            'articleId': '456',
            'title': '另一篇新闻',
            'url': 'https://www.zaobao.com/news/china/story20261030-456',
          },
          if (loadedOlder)
            {
              'articleId': '789',
              'title': '前一天的新闻',
              'url': 'https://www.zaobao.com/news/china/story20261029-789',
            },
        ];
        items.insertAll(2, [
          for (var i = 0; i < extraItems; i++)
            {
              'articleId': '${1000 + i}',
              'title': '第${i + 3}篇中国新闻，测试连续滚动排版',
              'url':
                  'https://www.zaobao.com/news/china/story20261030-${1000 + i}',
            },
        ]);
        return {
          'fetchedAt': '2026-10-30T02:00:00+00:00',
          'hasMore': paged && !loadedOlder,
          'total': items.length,
          'nextOffset': null,
          'items': items.skip(params?['offset'] as int? ?? 0).toList(),
        };
      case 'zaobao.feed.more':
        loadedOlder = true;
        return {'jobId': 'more-1'};
      case 'zaobao.article.get':
        if (params?['articleId'] == '123' && delayedArticle != null) {
          return delayedArticle!.future;
        }
        final second = params?['articleId'] == '456';
        return {
          'cached': cached || fetched,
          'article': cached || fetched
              ? {
                  'articleId': second ? '456' : '123',
                  'title': second ? '另一篇新闻' : '测试中国新闻',
                  'url': 'https://www.zaobao.com/news/china/story20261030-123',
                  'author': '测试作者',
                  'publishedAt': '2026-10-30T09:42:00+08:00',
                  'contentState': preview ? 'preview' : 'full',
                  'blocks': [
                    {'type': 'p', 'text': second ? '另一篇独立正文。' : '这是独立提取的正文。'},
                  ],
                }
              : null,
        };
      case 'zaobao.article.fetch':
        fetched = true;
        return {'jobId': 'fetch-1'};
      case 'zaobao.feed.refresh':
        if (failRefresh) throw const EngineException('HTTP_ERROR', '网络暂不可用');
        return {'jobId': 'feed-1'};
      case 'zaobao.task.get':
        return {'state': 'succeeded'};
      default:
        return {'ok': true};
    }
  }
}

Future<void> mount(
  WidgetTester tester,
  NewsEngine engine, {
  Size size = const Size(1280, 900),
  Brightness brightness = Brightness.light,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [engineProvider.overrideWithValue(engine)],
      child: MaterialApp(
        theme: buildTheme(brightness),
        home: const Scaffold(body: ZaobaoView()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'dark narrow layout and reading use shared typography without overflow',
    (tester) async {
      await mount(
        tester,
        NewsEngine(),
        size: const Size(810, 700),
        brightness: Brightness.dark,
      );
      expect(tester.takeException(), isNull);
      expect(find.byType(Card), findsNothing);
      await tester.tap(find.text('测试中国新闻'));
      await tester.pumpAndSettle();
      expect(find.text('A-'), findsOneWidget);
      expect(find.text('A+'), findsOneWidget);
      expect(find.textContaining('这是独立提取的正文'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'scrolling near the bottom automatically appends an older page once',
    (tester) async {
      final engine = NewsEngine(paged: true, extraItems: 24);
      await mount(tester, engine);
      await tester.drag(
        find.byType(CustomScrollView).first,
        const Offset(0, -5000),
      );
      await tester.pumpAndSettle();
      expect(
        engine.calls.where((method) => method == 'zaobao.feed.more').length,
        1,
      );
      expect(engine.loadedOlder, isTrue);
    },
  );
  test(
    'completed task returns immediately without waiting for media',
    () async {
      final engine = NewsEngine();
      await ZaobaoClient(engine)
          .run(
            'zaobao.article.fetch',
            {'articleId': '123'},
            isCurrent: () => true,
            onJob: (_) {},
          )
          .timeout(const Duration(seconds: 2));
      expect(engine.calls.last, 'zaobao.task.get');
    },
  );
  testWidgets(
    'newspaper layout loads older entries without replacing current news',
    (tester) async {
      final engine = NewsEngine(paged: true);
      await mount(tester, engine);
      expect(find.byType(Card), findsNothing);
      expect(find.byType(ListTile), findsNothing);
      await tester.tap(find.text('加载更早的文章'));
      await tester.pumpAndSettle();
      expect(find.text('测试中国新闻'), findsOneWidget);
      expect(find.text('前一天的新闻'), findsOneWidget);
      expect(engine.calls.where((m) => m == 'zaobao.feed.more').length, 1);
    },
  );

  testWidgets('does not fetch while source is inactive', (tester) async {
    final engine = NewsEngine();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [engineProvider.overrideWithValue(engine)],
        child: const MaterialApp(
          home: Scaffold(body: ZaobaoView(active: false)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(engine.calls, isEmpty);
  });

  testWidgets('late response cannot overwrite a newly selected article', (
    tester,
  ) async {
    final engine = NewsEngine();
    engine.delayedArticle = Completer<Object?>();
    await mount(tester, engine);
    await tester.tap(find.text('测试中国新闻'));
    await tester.pump();
    await tester.tap(find.byTooltip('返回文章列表'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('另一篇新闻'));
    await tester.pumpAndSettle();
    engine.delayedArticle!.complete({'cached': false, 'article': null});
    await tester.pumpAndSettle();
    expect(find.textContaining('另一篇独立正文'), findsOneWidget);
    expect(engine.calls, isNot(contains('zaobao.article.fetch')));
  });

  testWidgets(
    'shows cached list, opens independently rendered article and returns',
    (tester) async {
      final engine = NewsEngine();
      await mount(tester, engine);
      expect(find.text('中国频道'), findsOneWidget);
      expect(engine.calls, isNot(contains('zaobao.article.fetch')));
      await tester.tap(find.text('测试中国新闻'));
      await tester.pumpAndSettle();
      expect(find.textContaining('这是独立提取的正文'), findsOneWidget);
      expect(find.text('测试作者'), findsOneWidget);
      expect(find.text('PDF'), findsNothing);
      await tester.tap(find.byTooltip('返回文章列表'));
      await tester.pumpAndSettle();
      expect(find.text('另一篇新闻'), findsOneWidget);
    },
  );

  testWidgets('cache miss fetches only the selected article', (tester) async {
    final engine = NewsEngine(cached: false);
    await mount(tester, engine);
    await tester.tap(find.text('测试中国新闻'));
    await tester.pumpAndSettle();
    expect(engine.calls.where((m) => m == 'zaobao.article.fetch').length, 1);
    expect(find.textContaining('这是独立提取的正文'), findsOneWidget);
  });

  testWidgets('preview is labelled and refresh failure preserves list', (
    tester,
  ) async {
    await mount(tester, NewsEngine(preview: true, failRefresh: true));
    await tester.tap(find.byTooltip('刷新文章列表'));
    await tester.pumpAndSettle();
    expect(find.text('测试中国新闻'), findsOneWidget);
    expect(find.textContaining('网络暂不可用'), findsWidgets);
    await tester.tap(find.text('测试中国新闻'));
    await tester.pumpAndSettle();
    expect(find.textContaining('当前为可访问的预览'), findsOneWidget);
  });
}
