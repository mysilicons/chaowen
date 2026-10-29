import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/engine_client.dart';
import '../core/models.dart';

/// 由 main.dart 在启动时覆盖注入。
final engineProvider = Provider<EngineClient>(
  (ref) => throw UnimplementedError('engine 未注入'),
);

final selectedDateProvider = NotifierProvider<SelectedDate, DateTime>(SelectedDate.new);

class SelectedDate extends Notifier<DateTime> {
  @override
  DateTime build() => _dateOnly(DateTime.now());

  void select(DateTime value) => state = _dateOnly(value);

  void moveBy(int days) => state = state.add(Duration(days: days));
}

final visibleMonthProvider = NotifierProvider<VisibleMonth, DateTime>(VisibleMonth.new);

class VisibleMonth extends Notifier<DateTime> {
  @override
  DateTime build() {
    final now = DateTime.now();
    return DateTime(now.year, now.month);
  }

  void select(DateTime value) => state = DateTime(value.year, value.month);

  void shift(int months) => state = DateTime(state.year, state.month + months);
}

/// 某日期的整期目录。key 为 `YYYY-MM-DD`。
final issueProvider = FutureProvider.family<Issue, String>((ref, isoDate) async {
  final engine = ref.watch(engineProvider);
  final raw = await engine.call('issue.parse', {'date': isoDate});
  return Issue.fromJson(raw is Map<String, dynamic> ? raw : const {});
});

/// 某月的归档状态。key 为 `YYYY-MM`。
final monthStatusProvider =
    FutureProvider.family<Map<String, DayStatus>, String>((ref, yyyymm) async {
  final engine = ref.watch(engineProvider);
  final parts = yyyymm.split('-');
  final raw = await engine.call('library.month', {
    'year': int.parse(parts[0]),
    'month': int.parse(parts[1]),
  });
  final rows = raw is List ? raw : const [];
  return {
    for (final row in rows.whereType<Map<String, dynamic>>())
      if (row['date'] is String) row['date'] as String: DayStatus.fromJson(row),
  };
});

class DownloadJob {
  DownloadJob({required this.jobId, required this.date});

  final String jobId;
  final String date;
  int done = 0;
  int total = 0;
  int currentPage = 0;
  String status = 'running';
  String? error;

  double get progress => total == 0 ? 0 : done / total;
}

final queueProvider = NotifierProvider<QueueNotifier, List<DownloadJob>>(QueueNotifier.new);

class QueueNotifier extends Notifier<List<DownloadJob>> {
  @override
  List<DownloadJob> build() {
    final engine = ref.watch(engineProvider);
    final subscription = engine.events.listen(_apply);
    ref.onDispose(subscription.cancel);
    return const [];
  }

  void _apply(EngineEvent event) {
    final jobId = event.data['jobId'] as String?;
    if (jobId == null) return;

    switch (event.name) {
      case 'download.progress':
        _update(jobId, (job) {
          job.done = (event.data['done'] as num?)?.toInt() ?? job.done;
          job.total = (event.data['total'] as num?)?.toInt() ?? job.total;
          job.currentPage = (event.data['pageNo'] as num?)?.toInt() ?? job.currentPage;
        });
      case 'issue.archived':
        _update(jobId, (job) => job.status = 'archived');
      case 'job.finished':
        _update(jobId, (job) {
          final ok = event.data['ok'] == true;
          job.status = ok ? 'finished' : 'failed';
          final error = event.data['error'];
          if (error is Map<String, dynamic>) {
            job.error = error['code'] as String?;
          }
        });
      default:
        return;
    }
  }

  void _update(String jobId, void Function(DownloadJob) mutate) {
    final index = state.indexWhere((job) => job.jobId == jobId);
    if (index < 0) return;
    final job = state[index];
    mutate(job);
    state = [...state];
  }

  void add(DownloadJob job) => state = [...state, job];

  void clearFinished() =>
      state = state.where((job) => job.status == 'running').toList(growable: false);
}

DateTime _dateOnly(DateTime value) => DateTime(value.year, value.month, value.day);

String isoDate(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';

String isoMonth(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}';
