import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models.dart';
import '../state/providers.dart';
import '../theme/palette.dart';
import '../widgets/month_calendar.dart';
import '../widgets/page_thumb.dart';

class LibraryView extends ConsumerStatefulWidget {
  const LibraryView({super.key});
  @override
  ConsumerState<LibraryView> createState() => _LibraryViewState();
}

class _LibraryViewState extends ConsumerState<LibraryView> {
  bool _calendarOpen = false;
  static const _wd = ['一', '二', '三', '四', '五', '六', '日'];

  @override
  Widget build(BuildContext context) {
    final date = ref.watch(selectedDateProvider);
    final iso = isoDate(date);
    final issue = ref.watch(issueProvider(iso));
    final statuses = ref.watch(monthStatusProvider(isoMonth(date))).value ??
        const <String, DayStatus>{};
    final archived = statuses[iso]?.state == DayState.archived;
    final running = ref
        .watch(queueProvider)
        .where((job) => job.date == iso && job.status == 'running')
        .firstOrNull;

    return Stack(children: [
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _header(date),
        AnimatedSize(
          duration: const Duration(milliseconds: 190),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: _calendarOpen
              ? const Padding(
                  padding: EdgeInsets.fromLTRB(20, 0, 20, 6),
                  child: MonthCalendar())
              : const SizedBox(width: double.infinity),
        ),
        if (!_calendarOpen) _weekStrip(date, statuses),
        const SizedBox(height: 4),
        Divider(height: 1, color: context.colors.border),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 6),
          child: Row(children: [
            Text(
              '${date.year}年${date.month}月${date.day}日 星期${_wd[date.weekday - 1]}',
              style: TextStyle(
                fontFamily: AppFonts.serif,
                fontFamilyFallback: AppFonts.fallback,
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: context.colors.text,
              ),
            ),
            const SizedBox(width: 10),
            if (issue.value != null)
              Text('· ${issue.value!.pageCount} 版',
                  style: TextStyle(fontSize: 12, color: context.colors.text2)),
          ]),
        ),
        Expanded(child: _grid(iso, issue)),
      ]),
      if (!archived)
        Positioned(
          right: 26,
          bottom: 22,
          child: SizedBox(
            width: 48,
            height: 48,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // 只有真正在下载时才画进度环：
                // value 为 null 的 CircularProgressIndicator 是"无限转圈"，会让人以为一直在下载
                if (running != null)
                  SizedBox(
                    width: 48,
                    height: 48,
                    child: CircularProgressIndicator(
                      value: running.progress,
                      strokeWidth: 2.5,
                      backgroundColor: context.colors.brand.withValues(alpha: 0.15),
                      valueColor: AlwaysStoppedAnimation(context.colors.brand),
                    ),
                  ),
                FloatingActionButton(
                  onPressed: running == null ? () => _download(iso) : null,
                  backgroundColor: context.colors.brand,
                  foregroundColor: Colors.white,
                  elevation: 2,
                  mini: true,
                  shape: const CircleBorder(),
                  child: Icon(
                    running == null ? Icons.download_outlined : Icons.downloading,
                    size: 20,
                  ),
                ),
              ],
            ),
          ),
        ),
    ]);
  }

  Widget _header(DateTime date) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 18, 6),
        child: Row(children: [
          Text('${date.year}年${date.month}月',
              style: const TextStyle(
                fontFamily: AppFonts.serif,
                fontFamilyFallback: AppFonts.fallback,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              )),
          const Spacer(),
          TextButton.icon(
            onPressed: () => setState(() => _calendarOpen = !_calendarOpen),
            icon: Icon(_calendarOpen ? Icons.expand_less : Icons.expand_more, size: 18),
            label: Text(_calendarOpen ? '收起月历' : '选择日期',
                style: const TextStyle(fontSize: 12)),
            style: TextButton.styleFrom(foregroundColor: context.colors.text2),
          ),
          TextButton(
            onPressed: () {
              final now = DateTime.now();
              ref.read(visibleMonthProvider.notifier).select(now);
              ref.read(selectedDateProvider.notifier).select(now);
            },
            child: const Text('今天', style: TextStyle(fontSize: 12)),
          ),
        ]),
      );

  Widget _weekStrip(DateTime selected, Map<String, DayStatus> statuses) {
    final today = DateTime.now();
    final monday = selected.subtract(Duration(days: selected.weekday - 1));
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(children: [
        _arrow(Icons.chevron_left,
            () => ref.read(selectedDateProvider.notifier)
                .select(selected.subtract(const Duration(days: 7)))),
        for (var i = 0; i < 7; i++)
          Expanded(
            child: _cell(
              monday.add(Duration(days: i)),
              selected,
              today,
              statuses[isoDate(monday.add(Duration(days: i)))],
            ),
          ),
        _arrow(Icons.chevron_right,
            () => ref.read(selectedDateProvider.notifier)
                .select(selected.add(const Duration(days: 7)))),
      ]),
    );
  }

  Widget _arrow(IconData icon, VoidCallback onTap) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(icon, size: 18, color: context.colors.text2),
        ),
      );

  Widget _cell(DateTime day, DateTime selected, DateTime today, DayStatus? status) {
    final isToday = isoDate(day) == isoDate(today);
    final isSelected = isoDate(day) == isoDate(selected);
    final future = day.isAfter(today);
    return InkWell(
      onTap: future ? null : () => ref.read(selectedDateProvider.notifier).select(day),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        height: 44,
        margin: const EdgeInsets.symmetric(horizontal: 2),
        decoration: BoxDecoration(
          color: isSelected ? context.colors.brand : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: isToday && !isSelected ? context.colors.brand : Colors.transparent),
        ),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(_wd[day.weekday - 1],
              style: TextStyle(
                  fontSize: 9,
                  color: isSelected
                      ? Colors.white70
                      : future
                          ? context.colors.border
                          : context.colors.text2)),
          const SizedBox(height: 1),
          Text('${day.day}',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w400,
                  color: isSelected
                      ? Colors.white
                      : future
                          ? context.colors.border
                          : context.colors.text)),
          const SizedBox(height: 1),
          Container(
            width: 3,
            height: 3,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: status?.state == DayState.archived
                  ? (isSelected ? Colors.white : context.colors.success)
                  : Colors.transparent,
            ),
          ),
        ]),
      ),
    );
  }

  Widget _grid(String iso, AsyncValue<Issue> issue) => issue.when(
        loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
        error: (e, _) => Center(
          child: Text('无法获取该日版面\n$e',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: context.colors.text2)),
        ),
        data: (data) => data.pages.isEmpty
            ? Center(
                child: Text('该日期没有版面', style: TextStyle(color: context.colors.text2)))
            : LayoutBuilder(builder: (context, c) {
                final columns = (c.maxWidth / 150).floor().clamp(3, 8);
                return GridView.builder(
                  padding: const EdgeInsets.fromLTRB(24, 2, 24, 24),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    mainAxisSpacing: 14,
                    crossAxisSpacing: 14,
                    childAspectRatio: 0.60,
                  ),
                  itemCount: data.pages.length,
                  itemBuilder: (context, i) => PageThumb(
                    date: iso,
                    page: data.pages[i],
                    onTap: () => _open(data.pages[i].no, iso),
                  ),
                );
              }),
      );

  void _open(int no, String iso) {
    ref.read(readerTargetProvider.notifier).open(iso, no);
    ref.read(readerPageProvider.notifier).select(no);
    ref.read(shellIndexProvider.notifier).select(1);
  }

  Future<void> _download(String iso) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(engineProvider).call('download.start', {'date': iso});
      messenger.showSnackBar(const SnackBar(content: Text('已开始下载本期')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('下载失败：$e')));
    }
  }
}
