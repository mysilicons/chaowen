import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models.dart';
import '../core/app_log.dart';
import '../core/zaobao_client.dart';
import '../core/zaobao_models.dart';
import '../state/providers.dart';
import '../theme/palette.dart';
import '../widgets/article_body.dart';
import '../widgets/reader_controls.dart';
import '../widgets/zaobao_feed.dart';

/// Kept alive in the shell; it makes no requests until the user selects this source.
class ZaobaoView extends ConsumerStatefulWidget {
  const ZaobaoView({super.key, this.active = true});
  final bool active;

  @override
  ConsumerState<ZaobaoView> createState() => _ZaobaoViewState();
}

class _ZaobaoViewState extends ConsumerState<ZaobaoView> {
  final _listScroll = ScrollController();
  final _directoryScroll = ScrollController();
  final _articleScroll = ScrollController();
  List<ZaobaoItem> _items = [];
  ZaobaoItem? _selected;
  ZaobaoArticle? _article;
  String? _fetchedAt;
  String? _error;
  String? _job;
  bool _busy = false;
  bool _supported = true;
  int _generation = 0;
  bool _loadingMore = false;
  bool _hasMore = false;
  int? _nextOffset;
  String? _moreError;
  int _sessionGeneration = 0;
  Future<void>? _pendingMore;
  bool _advancing = false;

  bool get _canLoadMore => _hasMore || _nextOffset != null;

  ZaobaoClient get api => ZaobaoClient(ref.read(engineProvider));

  @override
  void initState() {
    super.initState();
    _listScroll.addListener(_onScroll);
    _directoryScroll.addListener(_onDirectoryScroll);
    if (widget.active) _start();
  }

  @override
  void didUpdateWidget(covariant ZaobaoView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) _start();
    if (!widget.active && oldWidget.active) {
      _generation++;
      _invalidateSession();
      setState(() {
        _items = [];
        _article = null;
        _selected = null;
        _busy = false;
        _loadingMore = false;
        _job = null;
      });
      unawaited(_resetSession());
    }
  }

  void _start() {
    unawaited(_load());
  }

  @override
  void dispose() {
    _generation++;
    _invalidateSession();
    _listScroll.dispose();
    _directoryScroll.dispose();
    _articleScroll.dispose();
    super.dispose();
  }

  bool _current(int token) => mounted && widget.active && token == _generation;

  bool _sessionCurrent(int token) =>
      mounted && widget.active && token == _sessionGeneration;

  void _invalidateSession() {
    _sessionGeneration++;
    _pendingMore = null;
    _loadingMore = false;
    _advancing = false;
  }

  Future<void> _resetSession() async {
    try {
      await api.call('zaobao.session.reset');
    } catch (error, stack) {
      AppLog.capture('zaobao.reset.failed', error, stack);
    }
  }

  Future<void> _load() async {
    final token = ++_generation;
    _invalidateSession();
    setState(() {
      _busy = true;
      _error = null;
      _items = [];
      _article = null;
      _selected = null;
      _fetchedAt = null;
      _hasMore = false;
      _nextOffset = null;
      _moreError = null;
      _loadingMore = false;
    });
    try {
      final hello = await api.call('hello');
      if (!_current(token)) return;
      _supported = (hello['features'] as Map?)?['zaobaoReaderV1'] == true;
      if (!_supported) {
        throw const EngineException('VERSION', '当前引擎不支持早报阅读，请使用配套的新版本引擎');
      }
      await api.call('zaobao.session.reset');
      if (!_current(token)) return;
      {
        await api.run(
          'zaobao.feed.refresh',
          {},
          isCurrent: () => _current(token),
          onJob: (job) => setState(() => _job = job),
        );
        await _readFeed(token);
      }
    } catch (error) {
      if (_current(token)) setState(() => _error = _message(error));
    } finally {
      if (_current(token)) {
        setState(() {
          _busy = false;
          _job = null;
        });
      }
    }
  }

  Future<void> _readFeed(int token) async {
    final data = await api.call('zaobao.feed.get');
    if (!_current(token)) return;
    final items = (data['items'] as List<dynamic>? ?? [])
        .map((value) => ZaobaoItem.fromJson(value as Map<String, dynamic>))
        .toList();
    setState(() {
      _items = items;
      _fetchedAt = data['fetchedAt'] as String?;
      _hasMore = data['hasMore'] == true;
      _nextOffset = data['nextOffset'] as int?;
      _moreError = null;
    });
  }

  void _onScroll() {
    if (_selected == null) _loadNearEnd(_listScroll);
  }

  void _onDirectoryScroll() {
    if (_selected != null) _loadNearEnd(_directoryScroll);
  }

  void _loadNearEnd(ScrollController controller) {
    if (widget.active &&
        !_loadingMore &&
        _moreError == null &&
        _canLoadMore &&
        controller.hasClients &&
        controller.position.extentAfter < 280) {
      unawaited(_more());
    }
  }

  Future<void> _more() {
    if (_pendingMore case final pending?) return pending;
    if (!_canLoadMore) return Future.value();
    final request = _loadMore(_sessionGeneration);
    _pendingMore = request;
    unawaited(
      request.whenComplete(() {
        if (identical(_pendingMore, request)) _pendingMore = null;
      }),
    );
    return request;
  }

  Future<void> _loadMore(int token) async {
    setState(() {
      _loadingMore = true;
      _moreError = null;
    });
    try {
      // Reuse pages only within this active in-memory session.
      var data = await api.call('zaobao.feed.get', {'offset': _items.length});
      if (!_sessionCurrent(token)) return;
      if ((data['items'] as List<dynamic>? ?? []).isEmpty &&
          data['hasMore'] == true) {
        await api.run(
          'zaobao.feed.more',
          {},
          isCurrent: () => _sessionCurrent(token),
          onJob: (_) {},
        );
        data = await api.call('zaobao.feed.get', {'offset': _items.length});
      }
      if (!_sessionCurrent(token)) return;
      final known = _items.map((item) => item.id).toSet();
      final added = (data['items'] as List<dynamic>? ?? [])
          .map((value) => ZaobaoItem.fromJson(value as Map<String, dynamic>))
          .where((item) => known.add(item.id));
      setState(() {
        _items = [..._items, ...added];
        _hasMore = data['hasMore'] == true;
        _nextOffset = data['nextOffset'] as int?;
      });
    } catch (error) {
      if (_sessionCurrent(token)) setState(() => _moreError = _message(error));
    } finally {
      if (_sessionCurrent(token)) setState(() => _loadingMore = false);
    }
  }

  Future<void> _next() async {
    if (_busy || _advancing) return;
    final selected = _selected;
    if (selected == null) return;
    final session = _sessionGeneration;
    final selection = _generation;
    setState(() => _advancing = true);
    try {
      var index = _items.indexWhere((item) => item.id == selected.id);
      if (index < 0) return;
      if (index == _items.length - 1 && _canLoadMore) await _more();
      if (!_sessionCurrent(session) || !_current(selection)) return;
      index = _items.indexWhere((item) => item.id == selected.id);
      if (index >= 0 && index + 1 < _items.length) {
        await _open(_items[index + 1]);
      }
    } finally {
      if (_sessionCurrent(session)) setState(() => _advancing = false);
    }
  }

  Future<void> _open(ZaobaoItem item, {bool refresh = false}) async {
    final previousJob = _job;
    final token = ++_generation;
    setState(() {
      _selected = item;
      _article = null;
      _error = null;
      _busy = true;
      _job = null;
    });
    if (_articleScroll.hasClients) _articleScroll.jumpTo(0);
    try {
      if (previousJob != null) {
        await api.call('zaobao.task.cancel', {'jobId': previousJob});
      }
      if (!_current(token)) return;
      await _readArticle(item.id, token);
      if (!_current(token)) return;
      if (_article == null || refresh) {
        await api.run(
          'zaobao.article.fetch',
          {'articleId': item.id, 'refresh': refresh},
          isCurrent: () => _current(token),
          onJob: (job) => setState(() => _job = job),
        );
        await _readArticle(item.id, token);
      }
      if (_current(token) && _article != null) {
        await api.call('zaobao.read.set', {'articleId': item.id, 'read': true});
        if (_current(token)) {
          setState(
            () => _items = _items
                .map((entry) => entry.id == item.id ? entry.markRead() : entry)
                .toList(),
          );
        }
      }
    } catch (error) {
      if (_current(token)) setState(() => _error = _message(error));
    } finally {
      if (_current(token)) {
        setState(() {
          _busy = false;
          _job = null;
        });
      }
    }
  }

  Future<void> _readArticle(String id, int token) async {
    try {
      final article = await api.article(id);
      if (_current(token) && article != null) {
        setState(() => _article = article);
      }
    } catch (error) {
      if (_current(token)) setState(() => _error = _message(error));
    }
  }

  Future<void> _back() async {
    final job = _job;
    ++_generation;
    setState(() {
      _selected = null;
      _article = null;
      _busy = false;
      _job = null;
      _error = null;
    });
    if (job != null) {
      try {
        await api.call('zaobao.task.cancel', {'jobId': job});
      } catch (error) {
        if (mounted) setState(() => _error = _message(error));
      }
    }
  }

  Future<void> _cancel() async {
    final job = _job;
    if (job == null) return;
    try {
      await api.call('zaobao.task.cancel', {'jobId': job});
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    }
  }

  Future<void> _original() async {
    final item = _selected;
    if (item == null) return;
    try {
      final result = await api.call('zaobao.original.open', {
        'articleId': item.id,
      });
      if (result['ok'] != true) {
        throw const EngineException('BROWSER', '无法打开系统浏览器');
      }
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    }
  }

  Future<void> _showLogs() async {
    try {
      await api.call('storage.reveal', {'path': AppLog.directory});
    } catch (error, stack) {
      AppLog.capture('logs.open.failed', error, stack);
      if (mounted) setState(() => _error = '无法打开日志目录');
    }
  }

  @override
  Widget build(BuildContext context) {
    final scale = ref.watch(readerScaleProvider);
    final selected = _selected;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header(selected, scale),
        if (_busy) const LinearProgressIndicator(minHeight: 2),
        if (_error case final error?) _notice(error, error: true),
        if (selected != null && _moreError != null)
          _notice(_moreError!, error: true),
        if (selected != null && _article != null) ...[
          if (_article!.state == 'preview') _notice('当前为可访问的预览，请前往官网继续阅读'),
          if (_article!.state != 'preview' && _article!.state != 'full')
            _notice('无法确认内容是否完整，可查看原文'),
          if (_article!.warnings.isNotEmpty) _notice('部分内容未能完整提取，可查看原文'),
        ],
        Expanded(
          child: IndexedStack(
            index: selected == null ? 0 : 1,
            children: [_list(), _reader(scale)],
          ),
        ),
      ],
    );
  }

  Widget _header(ZaobaoItem? selected, double scale) => Container(
    height: 58,
    padding: const EdgeInsets.symmetric(horizontal: 14),
    decoration: BoxDecoration(
      border: Border(bottom: BorderSide(color: context.colors.border)),
    ),
    child: Row(
      children: [
        if (selected != null) ...[
          IconButton(
            onPressed: _back,
            tooltip: '返回文章列表',
            icon: const Icon(Icons.arrow_back_ios_new, size: 16),
            color: context.colors.text2,
          ),
          const SizedBox(width: 4),
        ] else
          const SizedBox(width: 10),
        Text(
          '联合早报',
          style: TextStyle(
            fontFamily: AppFonts.serif,
            fontFamilyFallback: AppFonts.fallback,
            fontSize: selected == null ? 20 : 16,
            fontWeight: FontWeight.w700,
            color: context.colors.text,
          ),
        ),
        const SizedBox(width: 12),
        if (selected != null)
          Text(
            '中国 · 文章阅读',
            style: TextStyle(fontSize: 12, color: context.colors.text2),
          ),
        const Spacer(),
        if (_busy)
          ReaderTextAction(
            label: '取消',
            onPressed: _job == null ? null : _cancel,
          ),
        if (selected != null) ...[
          ReaderFontControls(scale: scale),
          const SizedBox(width: 14),
          ReaderTextAction(
            label: '原文',
            icon: Icons.open_in_new,
            onPressed: _original,
          ),
        ] else ...[
          if (_fetchedAt != null)
            Text(
              '更新于 ${_displayTime(_fetchedAt)}',
              style: TextStyle(fontSize: 11, color: context.colors.text2),
            ),
          const SizedBox(width: 12),
          ReaderTextAction(
            label: '刷新',
            tooltip: '刷新文章列表',
            icon: Icons.refresh,
            onPressed: _busy || _loadingMore || !_supported
                ? null
                : () => _load(),
          ),
        ],
        ReaderTextAction(label: '日志', onPressed: _showLogs),
        if (selected != null)
          PopupMenuButton<String>(
            tooltip: '更多操作',
            iconSize: 17,
            icon: Icon(Icons.more_horiz, color: context.colors.text2, size: 18),
            onSelected: (action) {
              if (action == 'refresh') {
                unawaited(_open(selected, refresh: true));
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'refresh',
                enabled: !_busy,
                child: const Text('重新提取文章', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
      ],
    ),
  );

  Widget _list() {
    if (_items.isEmpty) return _empty(_busy ? '正在读取中国频道…' : '暂无文章，点击刷新重试');
    return ZaobaoFeed(
      items: _items,
      controller: _listScroll,
      onOpen: _open,
      footer: _paginationFooter(),
    );
  }

  Widget _paginationFooter() => Column(
    children: [
      if (_moreError != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            _moreError!,
            style: TextStyle(fontSize: 12, color: context.colors.text2),
          ),
        ),
      if (_loadingMore)
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  color: context.colors.text2,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '正在载入更早的文章…',
                style: TextStyle(fontSize: 12, color: context.colors.text2),
              ),
            ],
          ),
        )
      else if (_canLoadMore)
        TextButton.icon(
          onPressed: _busy ? null : _more,
          icon: const Icon(Icons.keyboard_arrow_down, size: 16),
          label: Text(
            _moreError == null ? '加载更早的文章' : '重试加载',
            style: const TextStyle(fontSize: 12),
          ),
          style: TextButton.styleFrom(foregroundColor: context.colors.text2),
        )
      else
        Padding(
          padding: const EdgeInsets.all(14),
          child: Text(
            '已读至当前列表末尾',
            style: TextStyle(fontSize: 11, color: context.colors.text2),
          ),
        ),
    ],
  );

  Widget _reader(double scale) {
    final index = _items.indexWhere((item) => item.id == _selected?.id);
    final body = Column(
      children: [
        Expanded(
          child: _article != null
              ? ArticleBody(
                  key: ValueKey(_selected?.id),
                  article: _article!.article,
                  scale: scale,
                  controller: _articleScroll,
                  missingImagePlaceholder: true,
                  remoteImages: true,
                  metadata:
                      '来源：联合早报${_article!.publishedAt == null ? '' : ' · ${_displayTime(_article!.publishedAt)}'}',
                )
              : _empty(_busy ? '正在提取文章正文…' : '正文暂不可用，请重试或查看原文'),
        ),
        Container(
          height: 50,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: context.colors.border)),
          ),
          child: Row(
            children: [
              TextButton.icon(
                onPressed: index > 0 ? () => _open(_items[index - 1]) : null,
                icon: const Icon(Icons.chevron_left, size: 18),
                label: const Text('上一篇'),
              ),
              const Spacer(),
              Text(
                '第 ${index + 1} / ${_items.length} 篇',
                style: TextStyle(fontSize: 12, color: context.colors.text2),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed:
                    index >= 0 &&
                        !_busy &&
                        !_advancing &&
                        (index < _items.length - 1 || _canLoadMore)
                    ? _next
                    : null,
                icon: const Icon(Icons.chevron_right, size: 18),
                iconAlignment: IconAlignment.end,
                label: Text(_advancing ? '正在加载…' : '下一篇'),
              ),
            ],
          ),
        ),
      ],
    );
    return LayoutBuilder(
      builder: (context, bounds) => Row(
        children: [
          if (bounds.maxWidth >= 1050) ...[
            SizedBox(
              width: 204,
              child: ListView.builder(
                controller: _directoryScroll,
                itemCount: _items.length + 1,
                padding: const EdgeInsets.symmetric(
                  vertical: 12,
                  horizontal: 8,
                ),
                itemBuilder: (context, i) => i == _items.length
                    ? _paginationFooter()
                    : InkWell(
                        onTap: () => _open(_items[i]),
                        borderRadius: BorderRadius.circular(6),
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 4),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: i == index
                                ? context.colors.brand.withValues(alpha: .08)
                                : null,
                            borderRadius: BorderRadius.circular(6),
                            border: Border(
                              left: BorderSide(
                                width: 3,
                                color: i == index
                                    ? context.colors.brand
                                    : Colors.transparent,
                              ),
                            ),
                          ),
                          child: Text(
                            _items[i].title,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: AppFonts.serif,
                              fontFamilyFallback: AppFonts.fallback,
                              fontSize: 12,
                              height: 1.6,
                              color: i == index
                                  ? context.colors.brand
                                  : context.colors.text2,
                            ),
                          ),
                        ),
                      ),
              ),
            ),
            VerticalDivider(width: 1, color: context.colors.border),
          ],
          Expanded(child: body),
        ],
      ),
    );
  }

  Widget _notice(String text, {bool error = false}) => Container(
    color: (error ? context.colors.brand : context.colors.gold).withValues(
      alpha: .08,
    ),
    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
    child: Text(
      text,
      style: TextStyle(fontSize: 13, color: context.colors.text2),
    ),
  );

  Widget _empty(String text) => Center(
    child: Padding(
      padding: const EdgeInsets.all(30),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(color: context.colors.text2),
      ),
    ),
  );

  String _message(Object error) =>
      error is EngineException ? error.message : '早报处理失败：$error';

  String _displayTime(String? value) {
    if (value == null) return '尚未更新';
    final time = DateTime.tryParse(value)?.toLocal();
    if (time == null) return value;
    String two(int n) => n.toString().padLeft(2, '0');
    return '${time.year}-${two(time.month)}-${two(time.day)} ${two(time.hour)}:${two(time.minute)}';
  }
}
