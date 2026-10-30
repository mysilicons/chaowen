import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdfrx/pdfrx.dart';

import '../core/models.dart';
import '../state/providers.dart';
import '../theme/palette.dart';
import '../widgets/article_body.dart';

class ReaderView extends ConsumerStatefulWidget {
  const ReaderView({super.key});

  @override
  ConsumerState<ReaderView> createState() => _ReaderViewState();
}

class _ReaderViewState extends ConsumerState<ReaderView> {
  final PdfViewerController _pdfController = PdfViewerController();

  // 一旦打开过就保持挂载：反复切换模式时不用重新加载几十 MB 的 PDF
  bool _pdfOpened = false;
  bool _textOpened = false;

  /// 每期只提醒一次，避免反复弹窗
  final Set<String> _prompted = {};
  StreamSubscription<EngineEvent>? _archiveSub;

  @override
  void dispose() {
    _archiveSub?.cancel();
    super.dispose();
  }

  /// 进入 PDF 模式但本期没下载时，问一次要不要现在下
  void _maybePrompt(String date, bool pdfReady, bool statusLoaded) {
    if (pdfReady || !statusLoaded) return;
    if (!_prompted.add(date)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => _askDownload(date));
  }

  Future<void> _askDownload(String date) async {
    if (!mounted) return;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: context.colors.paper,
        title: const Text(
          '本期还没下载',
          style: TextStyle(fontFamily: AppFonts.serif, fontFamilyFallback: AppFonts.fallback),
        ),
        content: const Text(
          'PDF 模式需要整期文件。现在下载吗？\n约 60 MB，低速下载约 1 分钟。',
          style: TextStyle(fontSize: 13, height: 1.6),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('先看文字'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(backgroundColor: context.colors.brand),
            child: const Text('下载本期'),
          ),
        ],
      ),
    );

    if (!mounted) return;
    if (accepted != true) {
      ref.read(readerModeProvider.notifier).select('text');
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(engineProvider).call('download.start', {'date': date});
      messenger.showSnackBar(const SnackBar(content: Text('已开始下载，完成后自动显示')));
      _watchArchive(date);
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text('下载失败：$error')));
      ref.read(readerModeProvider.notifier).select('text');
    }
  }

  void _watchArchive(String date) {
    _archiveSub?.cancel();
    _archiveSub = ref.read(engineProvider).events.listen((event) {
      if (event.name == 'issue.archived' && event.data['date'] == date) {
        ref.invalidate(issueStatusProvider(date));
        _archiveSub?.cancel();
      }
      if (event.name == 'job.finished' && event.data['date'] == date) {
        ref.invalidate(issueStatusProvider(date));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final target = ref.watch(readerTargetProvider);
    if (target == null) {
      return Center(
        child: Text('从书架选择一版开始阅读', style: TextStyle(color: context.colors.text2)),
      );
    }

    final pageNo = ref.watch(readerPageProvider);
    final mode = ref.watch(readerModeProvider);
    final scale = ref.watch(readerScaleProvider);
    final issue = ref.watch(issueProvider(target.date)).value;
    final statusAsync = ref.watch(issueStatusProvider(target.date));
    final status = statusAsync.value;
    final mergedPath = status?['mergedPath'] as String?;
    final jobs = ref.watch(queueProvider);
    final running = jobs
        .where((job) => job.date == target.date && job.status == 'running')
        .firstOrNull;
    final pdfReady = mergedPath != null && File(mergedPath).existsSync();
    if (mode == 'pdf') {
      _maybePrompt(target.date, pdfReady, statusAsync.hasValue);
    }
    final pages = issue?.pages ?? const <PageInfo>[];
    final page = pages.where((item) => item.no == pageNo).firstOrNull;

    return Column(
      children: [
        _ReaderBar(
          date: target.date,
          title: page?.title ?? '',
          pageNo: pageNo,
          mode: mode,
          scale: scale,
          onMode: (value) => ref.read(readerModeProvider.notifier).select(value),
          onBack: () => ref.read(shellIndexProvider.notifier).select(0),
        ),
        Divider(height: 1, color: context.colors.border),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _PageStrip(
                pages: pages,
                current: pageNo,
                onSelect: (no) {
                  ref.read(readerPageProvider.notifier).select(no);
                  if (mode == 'pdf' && mergedPath != null) {
                    _pdfController.goToPage(pageNumber: no);
                  }
                },
              ),
              VerticalDivider(width: 1, color: context.colors.border),
              Expanded(
                child: _body(
                  target.date,
                  pageNo,
                  page,
                  scale,
                  mode,
                  mergedPath,
                  running?.progress,
                  running?.currentPage ?? 0,
                  running?.total ?? 0,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _body(
    String date,
    int pageNo,
    PageInfo? page,
    double scale,
    String mode,
    String? mergedPath,
    double? progress,
    int currentPage,
    int total,
  ) {
    if (mode == 'pdf') _pdfOpened = true;
    if (mode == 'text') _textOpened = true;

    return IndexedStack(
      index: mode == 'pdf' ? 0 : 1,
      children: [
        _pdfOpened
            ? _PdfPane(
                path: mergedPath,
                pageNo: pageNo,
                controller: _pdfController,
                progress: progress,
                currentPage: currentPage,
                total: total,
              )
            : const SizedBox.shrink(),
        _textOpened
            ? _TextPane(
                key: ValueKey('text-$date-$pageNo'),
                date: date,
                pageNo: pageNo,
                page: page,
                scale: scale,
                onSwitchToPdf: () =>
                    ref.read(readerModeProvider.notifier).select('pdf'),
              )
            : const SizedBox.shrink(),
      ],
    );
  }
}

class _ReaderBar extends ConsumerWidget {
  const _ReaderBar({
    required this.date,
    required this.title,
    required this.pageNo,
    required this.mode,
    required this.scale,
    required this.onMode,
    required this.onBack,
  });

  final String date;
  final String title;
  final int pageNo;
  final String mode;
  final double scale;
  final ValueChanged<String> onMode;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      height: 58,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        children: [
          IconButton(
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back_ios_new, size: 16),
            color: context.colors.text2,
            tooltip: '返回书架',
          ),
          const SizedBox(width: 4),
          Text(
            date,
            style: const TextStyle(
              fontFamily: AppFonts.serif,
                  fontFamilyFallback: AppFonts.fallback,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            '第${pageNo.toString().padLeft(2, '0')}版 · $title',
            style: TextStyle(fontSize: 13, color: context.colors.text2),
          ),
          const Spacer(),
          // 字号控件在左、模式切换固定在最右：
          // 切到 PDF 时字号控件隐藏，模式开关不会跟着跳。
          SizedBox(
            width: 132,
            child: mode == 'text'
                ? Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      _ScaleButton(
                        label: 'A-',
                        onTap: () => ref.read(readerScaleProvider.notifier).step(-0.1),
                      ),
                      _ScaleButton(
                        label: 'A+',
                        onTap: () => ref.read(readerScaleProvider.notifier).step(0.1),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${(scale * 100).round()}%',
                        style: TextStyle(fontSize: 11, color: context.colors.text2),
                      ),
                    ],
                  )
                : const SizedBox.shrink(),
          ),
          const SizedBox(width: 14),
          _ModeSwitch(mode: mode, onChanged: onMode),
        ],
      ),
    );
  }
}

class _ScaleButton extends StatelessWidget {
  const _ScaleButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Text(label, style: TextStyle(fontSize: 12, color: context.colors.text2)),
      ),
    );
  }
}

class _ModeSwitch extends StatelessWidget {
  const _ModeSwitch({required this.mode, required this.onChanged});

  final String mode;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: context.colors.paper,
        borderRadius: BorderRadius.circular(7),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _segment(context, 'pdf', 'PDF', mode == 'pdf'),
          _segment(context, 'text', '文字', mode == 'text'),
        ],
      ),
    );
  }

  Widget _segment(BuildContext context, String value, String label, bool selected) {
    return InkWell(
      onTap: () => onChanged(value),
      borderRadius: BorderRadius.circular(5),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? context.colors.surface : Colors.transparent,
          borderRadius: BorderRadius.circular(5),
          boxShadow: selected
              ? const [
                  BoxShadow(color: Color(0x14000000), blurRadius: 4, offset: Offset(0, 1)),
                ]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            color: selected ? context.colors.text : context.colors.text2,
          ),
        ),
      ),
    );
  }
}

class _PageStrip extends StatelessWidget {
  const _PageStrip({required this.pages, required this.current, required this.onSelect});

  final List<PageInfo> pages;
  final int current;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    if (pages.isEmpty) return const SizedBox(width: 72);
    return SizedBox(
      width: 72,
      child: ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
        child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: pages.length,
        itemBuilder: (context, index) {
          final page = pages[index];
          final selected = page.no == current;
          return InkWell(
            onTap: () => onSelect(page.no),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: selected ? context.colors.brand.withValues(alpha: 0.10) : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
                border: Border(
                  left: BorderSide(
                    color: selected ? context.colors.brand : Colors.transparent,
                    width: 3,
                  ),
                ),
              ),
              child: Column(
                children: [
                  Text(
                    page.no.toString().padLeft(2, '0'),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                      color: selected ? context.colors.brand : context.colors.text,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    page.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 10, color: context.colors.text2),
                  ),
                ],
              ),
            ),
            );
          },
        ),
      ),
    );
  }
}

class _PdfPane extends StatelessWidget {
  const _PdfPane({
    required this.path,
    required this.pageNo,
    required this.controller,
    this.progress,
    this.currentPage = 0,
    this.total = 0,
  });

  final String? path;
  final int pageNo;
  final PdfViewerController controller;
  final double? progress;
  final int currentPage;
  final int total;

  @override
  Widget build(BuildContext context) {
    final file = path;
    if (file == null || !File(file).existsSync()) {
      if (progress != null) {
        return Center(
          child: SizedBox(
            width: 320,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('正在下载本期…', style: TextStyle(color: context.colors.text2)),
                const SizedBox(height: 6),
                Text(
                  '第 $currentPage 版 · $total 版',
                  style: TextStyle(fontSize: 12, color: context.colors.text2),
                ),
                const SizedBox(height: 14),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 5,
                    backgroundColor: context.colors.border,
                    valueColor: AlwaysStoppedAnimation(context.colors.brand),
                  ),
                ),
              ],
            ),
          ),
        );
      }
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.picture_as_pdf_outlined, size: 34, color: context.colors.text2),
            SizedBox(height: 10),
            Text('本期 PDF 未就绪', style: TextStyle(color: context.colors.text2)),
            SizedBox(height: 4),
            Text(
              '可以先看「文字」模式',
              style: TextStyle(fontSize: 12, color: context.colors.text2),
            ),
          ],
        ),
      );
    }

    return PdfViewer.file(
      file,
      key: ValueKey(file),
      controller: controller,
      initialPageNumber: pageNo,
      params: PdfViewerParams(backgroundColor: context.colors.paper, margin: 12),
    );
  }
}

/// 文字阅读：一次只显示一篇文章，底栏上一篇/下一篇，标题栏可下拉跳转。
class _TextPane extends ConsumerStatefulWidget {
  const _TextPane({
    super.key,
    required this.date,
    required this.pageNo,
    required this.page,
    required this.scale,
    required this.onSwitchToPdf,
  });

  final String date;
  final int pageNo;
  final PageInfo? page;
  final double scale;
  final VoidCallback onSwitchToPdf;

  @override
  ConsumerState<_TextPane> createState() => _TextPaneState();
}

class _TextPaneState extends ConsumerState<_TextPane> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(
      articlePageProvider((date: widget.date, no: widget.pageNo)),
    );

    return async.when(
      loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      error: (error, _) => _Message(
        icon: Icons.cloud_off_outlined,
        text: '正文抓取失败\n$error',
        action: TextButton(
          onPressed: () => ref.invalidate(
            articlePageProvider((date: widget.date, no: widget.pageNo)),
          ),
          child: const Text('重试'),
        ),
      ),
      data: (data) => _buildContent(data),
    );
  }

  Widget _buildContent(ArticlePage data) {
    if (data.kind == PageKind.empty || data.kind == PageKind.failed) {
      return _Message(
        icon: Icons.article_outlined,
        text: data.kind == PageKind.empty ? '本版无可提取正文' : '本版正文解析失败',
        action: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextButton(onPressed: widget.onSwitchToPdf, child: const Text('切换 PDF 阅读')),
            TextButton(
              onPressed: () => ref.invalidate(
                articlePageProvider((date: widget.date, no: widget.pageNo)),
              ),
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }

    final total = data.articles.length;
    final index = _index.clamp(0, total - 1);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (data.kind == PageKind.imageOnly) _imageOnlyBanner(),
        Expanded(child: _articleBody(data.articles[index], data)),
        _ArticleNav(
          index: index,
          total: total,
          titles: data.articles.map((a) => a.title).toList(growable: false),
          onSelect: (value) => setState(() => _index = value),
        ),
      ],
    );
  }

  Widget _imageOnlyBanner() {
    return Container(
      color: context.colors.gold.withValues(alpha: 0.12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Icon(Icons.image_outlined, size: 16, color: context.colors.gold),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '本版以图片为主，文字内容较少',
              style: TextStyle(fontSize: 12, color: context.colors.text2),
            ),
          ),
          TextButton(
            onPressed: widget.onSwitchToPdf,
            child: const Text('看 PDF', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Widget _articleBody(Article article, ArticlePage data) {
    final thumb = widget.page?.thumbUrl;
    return ArticleBody(
      article: article,
      scale: widget.scale,
      leading: data.kind == PageKind.imageOnly && thumb != null
          ? Padding(
              padding: const EdgeInsets.only(bottom: 22),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: Image.network(thumb, fit: BoxFit.fitWidth,
                  errorBuilder: (context, error, stack) => const SizedBox.shrink()),
              ),
            )
          : null,
    );
  }
}

class _ArticleNav extends StatelessWidget {
  const _ArticleNav({
    required this.index,
    required this.total,
    required this.titles,
    required this.onSelect,
  });

  final int index;
  final int total;
  final List<String> titles;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: context.colors.border)),
      ),
      child: Row(
        children: [
          TextButton.icon(
            onPressed: index > 0 ? () => onSelect(index - 1) : null,
            icon: const Icon(Icons.chevron_left, size: 18),
            label: const Text('上一篇'),
          ),
          const Spacer(),
          InkWell(
            onTap: () => _pick(context),
            borderRadius: BorderRadius.circular(6),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: context.colors.surface,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: context.colors.border),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '第 ${index + 1} / $total 篇',
                    style: TextStyle(fontSize: 12, color: context.colors.text),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.expand_more, size: 16, color: context.colors.text2),
                ],
              ),
            ),
          ),
          const Spacer(),
          TextButton.icon(
            onPressed: index < total - 1 ? () => onSelect(index + 1) : null,
            icon: const Icon(Icons.chevron_right, size: 18),
            iconAlignment: IconAlignment.end,
            label: const Text('下一篇'),
          ),
        ],
      ),
    );
  }

  Future<void> _pick(BuildContext context) async {
    final picked = await showDialog<int>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.28),
      builder: (dialogContext) => Dialog(
        backgroundColor: context.colors.paper,
        insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 60),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520, maxHeight: 560),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 18, 12, 12),
                child: Row(
                  children: [
                    const Text(
                      '本版文章',
                      style: TextStyle(
                        fontFamily: AppFonts.serif,
                        fontFamilyFallback: AppFonts.fallback,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '共 $total 篇',
                      style: TextStyle(fontSize: 12, color: context.colors.text2),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      icon: const Icon(Icons.close, size: 18),
                      color: context.colors.text2,
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: context.colors.border),
              Flexible(
                child: ListView.separated(
                  padding: EdgeInsets.zero,
                  itemCount: titles.length,
                  separatorBuilder: (_, _) =>
                      Divider(height: 1, color: context.colors.border),
                  itemBuilder: (context, i) {
                    final active = i == index;
                    return InkWell(
                      onTap: () => Navigator.of(dialogContext).pop(i),
                      child: Container(
                        color: active
                            ? context.colors.brand.withValues(alpha: 0.06)
                            : Colors.transparent,
                        padding: const EdgeInsets.fromLTRB(22, 15, 18, 15),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: 26,
                              child: Text(
                                '${i + 1}',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: active ? FontWeight.w700 : FontWeight.w400,
                                  color: active ? context.colors.brand : context.colors.text2,
                                ),
                              ),
                            ),
                            Expanded(
                              child: Text(
                                titles[i],
                                style: TextStyle(
                                  fontFamily: AppFonts.serif,
                                  fontFamilyFallback: AppFonts.fallback,
                                  fontSize: 14,
                                  height: 1.5,
                                  color: context.colors.text,
                                  fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                                ),
                              ),
                            ),
                            if (active)
                              Padding(
                                padding: EdgeInsets.only(left: 8),
                                child: Icon(Icons.check, size: 15, color: context.colors.brand),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (picked != null) onSelect(picked);
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.text, this.action});

  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 32, color: context.colors.text2),
          const SizedBox(height: 12),
          Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: context.colors.text2),
          ),
          if (action != null) ...[const SizedBox(height: 12), action!],
        ],
      ),
    );
  }
}
