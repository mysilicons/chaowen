import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdfrx/pdfrx.dart';

import '../core/models.dart';
import '../state/providers.dart';
import '../theme/tokens.dart';

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

  @override
  Widget build(BuildContext context) {
    final target = ref.watch(readerTargetProvider);
    if (target == null) {
      return const Center(
        child: Text('从书架选择一版开始阅读', style: TextStyle(color: AppColors.text2)),
      );
    }

    final pageNo = ref.watch(readerPageProvider);
    final mode = ref.watch(readerModeProvider);
    final scale = ref.watch(readerScaleProvider);
    final issue = ref.watch(issueProvider(target.date)).value;
    final status = ref.watch(issueStatusProvider(target.date)).value;
    final mergedPath = status?['mergedPath'] as String?;
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
        const Divider(height: 1, color: AppColors.border),
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
              const VerticalDivider(width: 1, color: AppColors.border),
              Expanded(child: _body(target.date, pageNo, page, scale, mode, mergedPath)),
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
  ) {
    if (mode == 'pdf') _pdfOpened = true;
    if (mode == 'text') _textOpened = true;

    return IndexedStack(
      index: mode == 'pdf' ? 0 : 1,
      children: [
        _pdfOpened
            ? _PdfPane(path: mergedPath, pageNo: pageNo, controller: _pdfController)
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
            color: AppColors.text2,
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
            style: const TextStyle(fontSize: 13, color: AppColors.text2),
          ),
          const Spacer(),
          _ModeSwitch(mode: mode, onChanged: onMode),
          const SizedBox(width: 16),
          if (mode == 'text') ...[
            _ScaleButton(
              label: 'A-',
              onTap: () => ref.read(readerScaleProvider.notifier).step(-0.1),
            ),
            _ScaleButton(
              label: 'A+',
              onTap: () => ref.read(readerScaleProvider.notifier).step(0.1),
            ),
            const SizedBox(width: 8),
            Text(
              '${(scale * 100).round()}%',
              style: const TextStyle(fontSize: 11, color: AppColors.text2),
            ),
          ],
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
        child: Text(label, style: const TextStyle(fontSize: 12, color: AppColors.text2)),
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
        color: const Color(0xFFF1EEE7),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _segment('pdf', 'PDF', mode == 'pdf'),
          _segment('text', '文字', mode == 'text'),
        ],
      ),
    );
  }

  Widget _segment(String value, String label, bool selected) {
    return InkWell(
      onTap: () => onChanged(value),
      borderRadius: BorderRadius.circular(5),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? Colors.white : Colors.transparent,
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
            color: selected ? AppColors.text : AppColors.text2,
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
                color: selected ? AppColors.brand.withValues(alpha: 0.10) : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
                border: Border(
                  left: BorderSide(
                    color: selected ? AppColors.brand : Colors.transparent,
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
                      color: selected ? AppColors.brand : AppColors.text,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    page.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 10, color: AppColors.text2),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _PdfPane extends StatelessWidget {
  const _PdfPane({required this.path, required this.pageNo, required this.controller});

  final String? path;
  final int pageNo;
  final PdfViewerController controller;

  @override
  Widget build(BuildContext context) {
    final file = path;
    if (file == null || !File(file).existsSync()) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.picture_as_pdf_outlined, size: 34, color: AppColors.text2),
            SizedBox(height: 10),
            Text('本期尚未下载，无法按 PDF 阅读', style: TextStyle(color: AppColors.text2)),
            SizedBox(height: 4),
            Text(
              '可以先看「文字」模式，或回书架下载本期',
              style: TextStyle(fontSize: 12, color: AppColors.text2),
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
      params: const PdfViewerParams(backgroundColor: Color(0xFFF1EEE7), margin: 12),
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
      color: AppColors.gold.withValues(alpha: 0.12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          const Icon(Icons.image_outlined, size: 16, color: AppColors.gold),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              '本版以图片为主，文字内容较少',
              style: TextStyle(fontSize: 12, color: AppColors.text2),
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
    final scale = widget.scale;
    final thumb = widget.page?.thumbUrl;

    return SelectionArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(28, 26, 28, 32),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 980),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (data.kind == PageKind.imageOnly && thumb != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 22),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: Image.network(
                        thumb,
                        fit: BoxFit.fitWidth,
                        errorBuilder: (context, error, stack) => const SizedBox.shrink(),
                      ),
                    ),
                  ),
                Text(
                  article.title,
                  style: TextStyle(
                    fontFamily: AppFonts.serif,
                  fontFamilyFallback: AppFonts.fallback,
                    fontSize: 22 * scale,
                    fontWeight: FontWeight.w700,
                    height: 1.5,
                    color: AppColors.text,
                  ),
                ),
                if (article.author != null && article.author!.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    article.author!,
                    style: TextStyle(fontSize: 12 * scale, color: AppColors.text2),
                  ),
                ],
                const SizedBox(height: 20),
                for (final block in article.blocks)
                  if (block.isImage)
                    _image(block, scale)
                  else if ((block.text ?? '').isNotEmpty)
                    Padding(
                      padding: EdgeInsets.only(bottom: 14 * scale),
                      child: Text(
                        '\u3000\u3000${block.text}',
                        style: TextStyle(
                          fontFamily: AppFonts.serif,
                  fontFamilyFallback: AppFonts.fallback,
                          fontSize: 17 * scale,
                          height: 1.9,
                          color: AppColors.text,
                        ),
                      ),
                    ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _image(Block block, double scale) {
    final path = block.local;
    if (path == null || !File(path).existsSync()) return const SizedBox.shrink();
    return Padding(
      padding: EdgeInsets.only(bottom: 16 * scale),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Image.file(
          File(path),
          fit: BoxFit.fitWidth,
          errorBuilder: (context, error, stack) => const SizedBox.shrink(),
        ),
      ),
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
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          TextButton.icon(
            onPressed: index > 0 ? () => onSelect(index - 1) : null,
            icon: const Icon(Icons.chevron_left, size: 18),
            label: const Text('上一篇'),
          ),
          const Spacer(),
          PopupMenuButton<int>(
            initialValue: index,
            onSelected: onSelect,
            tooltip: '本版文章',
            itemBuilder: (context) => [
              for (var i = 0; i < titles.length; i++)
                PopupMenuItem(
                  value: i,
                  child: SizedBox(
                    width: 420,
                    child: Text(
                      '${i + 1}. ${titles[i]}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                ),
            ],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '第 ${index + 1} / $total 篇',
                    style: const TextStyle(fontSize: 12, color: AppColors.text2),
                  ),
                  const Icon(Icons.expand_more, size: 16, color: AppColors.text2),
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
          Icon(icon, size: 32, color: AppColors.text2),
          const SizedBox(height: 12),
          Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, color: AppColors.text2),
          ),
          if (action != null) ...[const SizedBox(height: 12), action!],
        ],
      ),
    );
  }
}
