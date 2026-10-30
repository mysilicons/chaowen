import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models.dart';
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
  final _articleScroll = ScrollController();
  List<ZaobaoItem> _items = [];
  ZaobaoItem? _selected;
  ZaobaoArticle? _article;
  String? _fetchedAt;
  String? _error;
  String? _job;
  bool _busy = false;
  bool _started = false;
  bool _supported = true;
  int _generation = 0;
  bool _loadingMore = false;
  bool _hasMore = false;
  int? _nextOffset;
  String? _moreError;
  StreamSubscription<EngineEvent>? _updates;

  ZaobaoClient get api => ZaobaoClient(ref.read(engineProvider));

  @override
  void initState() {
    super.initState();
    _listScroll.addListener(_onScroll);
    _updates = ref.read(engineProvider).events.listen((event) {
      if (event.name == 'zaobao.article.updated' &&
          event.data['articleId'] == _selected?.id) {
        unawaited(_readArticle(_selected!.id, _generation));
      }
    });
    if (widget.active) _start();
  }

  @override
  void didUpdateWidget(covariant ZaobaoView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !_started) _start();
  }

  void _start() {
    _started = true;
    unawaited(_load());
  }

  @override
  void dispose() {
    _generation++;
    unawaited(_updates?.cancel());
    _listScroll.dispose();
    _articleScroll.dispose();
    super.dispose();
  }

  bool _current(int token) => mounted && token == _generation;

  Future<void> _load({bool refresh = false}) async {
    final token = ++_generation;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final hello = await api.call('hello');
      if (!_current(token)) return;
      _supported = (hello['features'] as Map?)?['zaobaoReaderV1'] == true;
      if (!_supported) {
        throw const EngineException('VERSION', '当前引擎不支持早报阅读，请使用配套的新版本引擎');
      }
      await _readFeed(token);
      if (!_current(token)) return;
      if (refresh || _items.isEmpty) {
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
    if (widget.active &&
        _selected == null &&
        !_busy &&
        !_loadingMore &&
        _moreError == null &&
        (_hasMore || _nextOffset != null) &&
        _listScroll.hasClients &&
        _listScroll.position.extentAfter < 280) {
      unawaited(_more());
    }
  }

  Future<void> _more() async {
    if (_loadingMore || _busy) return;
    setState(() {
      _loadingMore = true;
      _moreError = null;
    });
    try {
      // Read already downloaded pages first; navigating back never skips a page.
      var data = await api.call('zaobao.feed.get', {'offset': _items.length});
      if ((data['items'] as List<dynamic>? ?? []).isEmpty &&
          data['hasMore'] == true) {
        await api.run(
          'zaobao.feed.more',
          {},
          isCurrent: () => mounted,
          onJob: (_) {},
        );
        data = await api.call('zaobao.feed.get', {'offset': _items.length});
      }
      if (!mounted) return;
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
      if (mounted) setState(() => _moreError = _message(error));
    } finally {
      if (mounted) setState(() => _loadingMore = false);
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

  Future<void> _clear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清理早报缓存'),
        content: const Text('删除已缓存的早报正文和图片，保留文章列表和已读状态。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('清理'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await api.call('zaobao.cache.clear');
      if (mounted) await _readFeed(_generation);
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
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
        if (selected != null && _article != null) ...[
          if (_article!.state == 'preview') _notice('当前为可访问的预览，请前往官网继续阅读'),
          if (_article!.state != 'preview' && _article!.state != 'full')
            _notice('无法确认内容是否完整，可查看原文'),
          if (_article!.warnings.isNotEmpty) _notice('部分图片未能缓存，文字仍可阅读'),
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
                : () => _load(refresh: true),
          ),
        ],
        PopupMenuButton<String>(
          tooltip: '更多操作',
          iconSize: 17,
          icon: Icon(Icons.more_horiz, color: context.colors.text2, size: 18),
          onSelected: (action) {
            if (action == 'clear') unawaited(_clear());
            if (action == 'refresh' && selected != null) {
              unawaited(_open(selected, refresh: true));
            }
          },
          itemBuilder: (_) => [
            if (selected != null)
              PopupMenuItem(
                value: 'refresh',
                enabled: !_busy,
                child: const Text('重新提取文章', style: TextStyle(fontSize: 12)),
              ),
            PopupMenuItem(
              value: 'clear',
              enabled: !_busy && !_loadingMore && _supported,
              child: const Text('清理早报缓存', style: TextStyle(fontSize: 12)),
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
      footer: Column(
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
          else if (_hasMore || _nextOffset != null)
            TextButton.icon(
              onPressed: _busy ? null : _more,
              icon: const Icon(Icons.keyboard_arrow_down, size: 16),
              label: Text(
                _moreError == null ? '加载更早的文章' : '重试加载',
                style: const TextStyle(fontSize: 12),
              ),
              style: TextButton.styleFrom(
                foregroundColor: context.colors.text2,
              ),
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
      ),
    );
  }

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
                onPressed: index >= 0 && index < _items.length - 1
                    ? () => _open(_items[index + 1])
                    : null,
                icon: const Icon(Icons.chevron_right, size: 18),
                iconAlignment: IconAlignment.end,
                label: const Text('下一篇'),
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
                itemCount: _items.length,
                padding: const EdgeInsets.symmetric(
                  vertical: 12,
                  horizontal: 8,
                ),
                itemBuilder: (context, i) => InkWell(
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
