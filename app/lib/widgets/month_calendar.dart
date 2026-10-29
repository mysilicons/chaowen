import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models.dart';
import '../state/providers.dart';
import '../theme/palette.dart';

/// 月历：每格显示归档状态点。
class MonthCalendar extends ConsumerWidget {
  const MonthCalendar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final month = ref.watch(visibleMonthProvider);
    final selected = ref.watch(selectedDateProvider);
    final statuses =
        ref.watch(monthStatusProvider(isoMonth(month))).value ??
        const <String, DayStatus>{};

    final firstDay = DateTime(month.year, month.month, 1);
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    // 周一为第一列
    final leading = (firstDay.weekday - 1) % 7;
    final cells = leading + daysInMonth;
    final rows = ((cells + 6) ~/ 7);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            for (final label in const ['一', '二', '三', '四', '五', '六', '日'])
              Expanded(
                child: Center(
                  child: Text(
                    label,
                    style: TextStyle(fontSize: 12, color: context.colors.text2),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        for (var row = 0; row < rows; row++)
          Row(
            children: [
              for (var col = 0; col < 7; col++)
                Expanded(
                  child: _cell(
                    context,
                    ref,
                    index: row * 7 + col - leading,
                    daysInMonth: daysInMonth,
                    month: month,
                    selected: selected,
                    statuses: statuses,
                  ),
                ),
            ],
          ),
      ],
    );
  }

  Widget _cell(
    BuildContext context,
    WidgetRef ref, {
    required int index,
    required int daysInMonth,
    required DateTime month,
    required DateTime selected,
    required Map<String, DayStatus> statuses,
  }) {
    if (index < 0 || index >= daysInMonth) {
      return const SizedBox(height: 34);
    }

    final day = DateTime(month.year, month.month, index + 1);
    final isSelected =
        day.year == selected.year && day.month == selected.month && day.day == selected.day;
    final status = statuses[isoDate(day)];
    final future = day.isAfter(DateTime.now());

    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: future ? null : () {
        ref.read(selectedDateProvider.notifier).select(day);
        ref.read(visibleMonthProvider.notifier).select(day);
      },
      child: Container(
        height: 34,
        margin: const EdgeInsets.all(1.5),
        decoration: BoxDecoration(
          color: isSelected ? context.colors.brand : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: isSelected ? null : Border.all(color: Colors.transparent),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '${day.day}',
              style: TextStyle(
                fontSize: 13,
                color: isSelected
                    ? Colors.white
                    : future
                    ? context.colors.border
                    : context.colors.text,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
            const SizedBox(height: 2),
            _dot(context, status?.state, isSelected),
          ],
        ),
      ),
    );
  }

  Widget _dot(BuildContext context, DayState? state, bool isSelected) {
    final color = switch (state) {
      DayState.archived => isSelected ? Colors.white : context.colors.success,
      DayState.partial => isSelected ? Colors.white70 : context.colors.gold,
      DayState.downloading => isSelected ? Colors.white70 : context.colors.brand,
      DayState.failed => isSelected ? Colors.white70 : context.colors.brandHover,
      _ => Colors.transparent,
    };
    return Container(
      width: 4,
      height: 4,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}
