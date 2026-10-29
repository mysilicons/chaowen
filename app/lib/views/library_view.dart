import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models.dart';
import '../state/providers.dart';
import '../theme/tokens.dart';
import '../widgets/month_calendar.dart';
import '../widgets/page_thumb.dart';

class LibraryView extends ConsumerWidget {
  const LibraryView({super.key});

  static const _weekdays = ['一', '二', '三', '四', '五', '六', '日'];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final date = ref.watch(selectedDateProvider);
    final month = ref.watch(visibleMonthProvider);
    final iso = isoDate(date);
    final issue = ref.watch(issueProvider(iso));
    final statuses =
        ref.watch(monthStatusProvider(isoMonth(month))).value ??
        const <String, DayStatus>{};
    final dayStatus = statuses[iso];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _MonthHeader(month: month),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: const MonthCalendar(),
        ),
        const SizedBox(height: 12),
        const Divider(height: 1, color: AppColors.border),
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 18, 28, 10),
          child: Row(
            children: [
              Text(
                '${date.year}年${date.month}月${date.day}日 星期${_weekdays[date.weekday - 1]}',
                style: const TextStyle(
                  fontFamily: AppFonts.serif,
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                  color: AppColors.text,
                ),
              ),
              const SizedBox(width: 12),
              if (issue.value != null)
                Text(
                  '· ${issue.value!.pageCount} 版',
                  style: const TextStyle(fontSize: 13, color: AppColors.text2),
                ),
              const Spacer(),
              _StateBadge(state: dayStatus?.state),
            ],
          ),
        ),
        Expanded(child: _IssueBody(date: iso, issue: issue)),
        _ActionBar(date: iso, status: dayStatus),
      ],
    );
  }
}

class _MonthHeader extends ConsumerWidget {
  const _MonthHeader({required this.month});

  final DateTime month;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 22, 28, 12),
      child: Row(
        children: [
          Text(
            '${month.year}年${month.month}月',
            style: const TextStyle(
              fontFamily: AppFonts.serif,
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: AppColors.text,
            ),
          ),
          const Spacer(),
          _iconButton(Icons.chevron_left, () => ref.read(visibleMonthProvider.notifier).shift(-1)),
          const SizedBox(width: 4),
          _iconButton(Icons.chevron_right, () => ref.read(visibleMonthProvider.notifier).shift(1)),
          const SizedBox(width: 8),
          TextButton(
            onPressed: () {
              final now = DateTime.now();
              ref.read(visibleMonthProvider.notifier).select(now);
              ref.read(selectedDateProvider.notifier).select(now);
            },
            child: const Text('今天'),
          ),
        ],
      ),
    );
  }

  Widget _iconButton(IconData icon, VoidCallback onTap) => IconButton(
    onPressed: onTap,
    icon: Icon(icon, size: 20),
    color: AppColors.text2,
    visualDensity: VisualDensity.compact,
  );
}

class _StateBadge extends StatelessWidget {
  const _StateBadge({this.state});

  final DayState? state;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (state) {
      DayState.archived => ('已归档', AppColors.success),
      DayState.partial => ('部分下载', AppColors.gold),
      DayState.downloading => ('下载中', AppColors.brand),
      DayState.failed => ('下载失败', AppColors.brandHover),
      _ => ('未下载', AppColors.text2),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label, style: TextStyle(fontSize: 12, color: color)),
    );
  }
}

class _IssueBody extends StatelessWidget {
  const _IssueBody({required this.date, required this.issue});

  final String date;
  final AsyncValue<Issue> issue;

  @override
  Widget build(BuildContext context) {
    return issue.when(
      loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      error: (error, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_outlined, size: 32, color: AppColors.text2),
              const SizedBox(height: 12),
              Text(
                '无法获取该日版面\n$error',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, color: AppColors.text2),
              ),
            ],
          ),
        ),
      ),
      data: (data) => data.pages.isEmpty
          ? const Center(
              child: Text('该日期没有版面', style: TextStyle(color: AppColors.text2)),
            )
          : LayoutBuilder(
              builder: (context, constraints) {
                final columns = (constraints.maxWidth / 150).floor().clamp(3, 8);
                return GridView.builder(
                  padding: const EdgeInsets.fromLTRB(28, 4, 28, 12),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    mainAxisSpacing: 14,
                    crossAxisSpacing: 14,
                    childAspectRatio: 0.60,
                  ),
                  itemCount: data.pages.length,
                  itemBuilder: (context, index) {
                    final page = data.pages[index];
                    return PageThumb(
                      page: page,
                      onTap: () => _showPreview(context, page),
                    );
                  },
                );
              },
            ),
    );
  }

  void _showPreview(BuildContext context, PageInfo page) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.paper,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '第${page.no.toString().padLeft(2, '0')}版 · ${page.title}',
                style: const TextStyle(
                  fontFamily: AppFonts.serif,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              if (page.articles.isEmpty)
                const Text('本版无可提取标题', style: TextStyle(color: AppColors.text2))
              else
                ...page.articles.map(
                  (article) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Text(
                      '· ${article.title}',
                      style: const TextStyle(fontSize: 14, height: 1.6),
                    ),
                  ),
                ),
              const SizedBox(height: 14),
              const Text(
                '正文阅读将在 P3 接入',
                style: TextStyle(fontSize: 12, color: AppColors.text2),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionBar extends ConsumerWidget {
  const _ActionBar({required this.date, this.status});

  final String date;
  final DayStatus? status;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final archived = status?.state == DayState.archived;
    final bytes = status?.bytes ?? 0;

    return Container(
      padding: const EdgeInsets.fromLTRB(28, 12, 28, 18),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Text(
            archived ? '已归档 · ${(bytes / 1024 / 1024).toStringAsFixed(1)} MB' : '未归档',
            style: const TextStyle(fontSize: 12, color: AppColors.text2),
          ),
          const Spacer(),
          FilledButton.icon(
            onPressed: archived ? null : () => _download(context, ref),
            icon: const Icon(Icons.download_outlined, size: 18),
            label: Text(archived ? '已下载' : '下载本期'),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.brand,
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _download(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(engineProvider).call('download.start', {'date': date});
      messenger.showSnackBar(
        const SnackBar(content: Text('已加入下载队列，进度见「下载中心」')),
      );
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text('下载失败：$error')));
    }
  }
}
