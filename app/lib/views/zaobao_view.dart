import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models.dart';
import '../core/zaobao_client.dart';
import '../core/zaobao_models.dart';
import '../state/providers.dart';
import '../theme/palette.dart';
import '../widgets/article_body.dart';

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

  ZaobaoClient get api => ZaobaoClient(ref.read(engineProvider));

  @override
  void initState() {
    super.initState();
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
    });
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
          onProgress: () => _readArticle(item.id, token),
        );
        await _readArticle(item.id, token);
      }
      if (_current(token) && _article != null) {
        await api.call('zaobao.read.set', {'articleId': item.id, 'read': true});
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

  Future<void> _readArticle(String id, int token) async {
    final article = await api.article(id);
    if (_current(token) && article != null) setState(() => _article = article);
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
    try {
      if (mounted) await _readFeed(_generation);
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
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
            children: [
              _list(),
              _article != null
                  ? ArticleBody(
                      key: ValueKey(selected?.id),
                      article: _article!.article,
                      scale: scale,
                      controller: _articleScroll,
                      missingImagePlaceholder: true,
                      metadata:
                          '来源：联合早报${_article!.publishedAt == null ? '' : ' · ${_displayTime(_article!.publishedAt)}'}',
                    )
                  : _empty(_busy ? '正在提取文章正文…' : '正文暂不可用，请重试或查看原文'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _header(ZaobaoItem? selected, double scale) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
    decoration: BoxDecoration(
      border: Border(bottom: BorderSide(color: context.colors.border)),
    ),
    child: Row(
      children: [
        if (selected != null)
          IconButton(
            onPressed: _back,
            tooltip: '返回文章列表',
            icon: const Icon(Icons.arrow_back),
          ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                selected == null ? '联合早报' : '联合早报 · 中国',
                style: TextStyle(
                  fontFamily: AppFonts.serif,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: context.colors.text,
                ),
              ),
              Text(
                selected == null
                    ? '中国频道'
                    : (_busy ? '正在获取文章及图片，可先阅读文字' : '文章阅读'),
                style: TextStyle(color: context.colors.text2, fontSize: 12),
              ),
            ],
          ),
        ),
        if (_busy && _job != null)
          TextButton(onPressed: _cancel, child: const Text('取消任务')),
        if (selected != null) ...[
          IconButton(
            tooltip: '缩小字号',
            onPressed: scale > .85
                ? () => ref.read(readerScaleProvider.notifier).step(-.05)
                : null,
            icon: const Icon(Icons.text_decrease),
          ),
          IconButton(
            tooltip: '放大字号',
            onPressed: scale < 1.5
                ? () => ref.read(readerScaleProvider.notifier).step(.05)
                : null,
            icon: const Icon(Icons.text_increase),
          ),
          TextButton.icon(
            onPressed: _original,
            icon: const Icon(Icons.open_in_new, size: 16),
            label: const Text('原文'),
          ),
        ],
        IconButton(
          tooltip: selected == null ? '刷新文章列表' : '重新提取文章',
          onPressed: _busy || !_supported
              ? null
              : () => selected == null
                    ? _load(refresh: true)
                    : _open(selected, refresh: true),
          icon: const Icon(Icons.refresh),
        ),
        if (selected == null)
          IconButton(
            tooltip: '清理早报缓存',
            onPressed: _busy || !_supported ? null : _clear,
            icon: const Icon(Icons.cleaning_services_outlined),
          ),
      ],
    ),
  );

  Widget _list() {
    if (_items.isEmpty) return _empty(_busy ? '正在读取中国频道…' : '暂无文章，点击刷新重试');
    return ListView.builder(
      controller: _listScroll,
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 28),
      itemCount: _items.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              '本页 ${_items.length} 篇 · 最近更新 ${_displayTime(_fetchedAt)}',
              style: TextStyle(fontSize: 12, color: context.colors.text2),
            ),
          );
        }
        final item = _items[index - 1];
        return Card(
          margin: const EdgeInsets.only(bottom: 10),
          elevation: 0,
          color: context.colors.surface,
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 20,
              vertical: 12,
            ),
            leading: Icon(
              item.read ? Icons.check_circle_outline : Icons.article_outlined,
              color: item.read ? context.colors.text2 : context.colors.brand,
            ),
            title: Text(
              item.title,
              style: TextStyle(
                fontFamily: AppFonts.serif,
                fontFamilyFallback: AppFonts.fallback,
                fontSize: 18,
                height: 1.6,
                color: item.read ? context.colors.text2 : context.colors.text,
              ),
            ),
            subtitle: Text(
              [
                if (item.timeLabel != null) item.timeLabel!,
                if (item.read) '已读',
                if (item.cached) '已缓存正文',
              ].join(' · '),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _open(item),
          ),
        );
      },
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
