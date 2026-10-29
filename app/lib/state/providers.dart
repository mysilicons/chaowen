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
  String date;
  int done = 0;
  int total = 0;
  int currentPage = 0;
  String status = 'running';
  bool paused = false;
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
    final date = event.data['date'] as String? ?? '';

    switch (event.name) {
      case 'download.progress':
        _ensure(jobId, date);
        _update(jobId, (job) {
          job.done = (event.data['done'] as num?)?.toInt() ?? job.done;
          job.total = (event.data['total'] as num?)?.toInt() ?? job.total;
          job.currentPage = (event.data['pageNo'] as num?)?.toInt() ?? job.currentPage;
        });
      case 'batch.progress':
        _ensure(jobId, date);
        _update(jobId, (job) {
          // 批量任务按天推进，标题要跟着当前这一天走
          job.date = date;
          job.done = (event.data['index'] as num?)?.toInt() ?? job.done;
          job.total = (event.data['total'] as num?)?.toInt() ?? job.total;
        });
      case 'issue.archived':
        _update(jobId, (job) => job.status = 'archived');
        // 下载完成后把书架、月历、阅读器状态全部作废，否则界面还显示"未下载"
        if (date.isNotEmpty) {
          ref.invalidate(issueProvider(date));
          ref.invalidate(issueStatusProvider(date));
          ref.invalidate(monthStatusProvider(date.substring(0, 7)));
        }
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

  DownloadJob _ensure(String jobId, String date) {
    final index = state.indexWhere((job) => job.jobId == jobId);
    if (index >= 0) return state[index];
    final job = DownloadJob(jobId: jobId, date: date.isEmpty ? '批量' : date);
    state = [...state, job];
    return job;
  }

  void _update(String jobId, void Function(DownloadJob) mutate) {
    final index = state.indexWhere((job) => job.jobId == jobId);
    if (index < 0) return;
    final job = state[index];
    mutate(job);
    state = [...state];
  }

  void add(DownloadJob job) => state = [...state, job];

  void markPaused(String jobId, bool paused) {
    _update(jobId, (job) {
      job.paused = paused;
      job.status = paused ? 'paused' : 'running';
    });
  }

  void clearFinished() =>
      state = state.where((job) => job.status == 'running').toList(growable: false);
}

/// 深色模式开关（本次运行内有效）
final darkModeProvider = NotifierProvider<DarkMode, bool>(DarkMode.new);

class DarkMode extends Notifier<bool> {
  @override
  bool build() => false;

  void toggle() => state = !state;
}

/// 左侧栏是否折叠
final sidebarCollapsedProvider =
    NotifierProvider<SidebarCollapsed, bool>(SidebarCollapsed.new);

class SidebarCollapsed extends Notifier<bool> {
  @override
  bool build() => false;

  void toggle() => state = !state;
}

/// 主界面当前页：0 书架 / 1 下载中心 / 2 阅读器
final shellIndexProvider = NotifierProvider<ShellIndex, int>(ShellIndex.new);

class ShellIndex extends Notifier<int> {
  @override
  int build() => 0;

  void select(int value) => state = value;
}

/// 阅读目标：日期 + 版号
final readerTargetProvider =
    NotifierProvider<ReaderTarget, ({String date, int no})?>(ReaderTarget.new);

class ReaderTarget extends Notifier<({String date, int no})?> {
  @override
  ({String date, int no})? build() => null;

  void open(String date, int no) => state = (date: date, no: no);
}

/// 当前阅读的版号（与阅读目标分离，便于版条切换）
final readerPageProvider = NotifierProvider<ReaderPage, int>(ReaderPage.new);

class ReaderPage extends Notifier<int> {
  @override
  int build() => 1;

  void select(int value) => state = value;
}

final readerModeProvider = NotifierProvider<ReaderMode, String>(ReaderMode.new);

class ReaderMode extends Notifier<String> {
  @override
  String build() => 'text';

  void select(String value) => state = value;
}

final readerScaleProvider = NotifierProvider<ReaderScale, double>(ReaderScale.new);

class ReaderScale extends Notifier<double> {
  @override
  double build() => 1.0;

  void step(double delta) {
    final next = (state + delta).clamp(0.85, 1.5);
    state = double.parse(next.toStringAsFixed(2));
  }
}

/// 引擎信息（版本、下载目录、缓存目录）
final helloProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final raw = await ref
      .watch(engineProvider)
      .call('hello', {'protocol': 1, 'client': 'rmrb-reader/0.1.0'});
  return raw is Map<String, dynamic> ? raw : const <String, dynamic>{};
});

/// 某期是否已合并（阅读器需要 mergedPath）
final issueStatusProvider =
    FutureProvider.family<Map<String, dynamic>, String>((ref, isoDate) async {
  final raw = await ref.watch(engineProvider).call('issue.status', {'date': isoDate});
  return raw is Map<String, dynamic> ? raw : const <String, dynamic>{};
});

/// 单版详情（缩略图 / PDF 直链）——未下载过的日期也能拿到每一版的图
final pageDetailProvider =
    FutureProvider.family<PageInfo, ({String date, int no})>((ref, key) async {
  final raw = await ref
      .watch(engineProvider)
      .call('issue.page', {'date': key.date, 'pageNo': key.no});
  return PageInfo.fromJson(raw is Map<String, dynamic> ? raw : const {});
});

/// 某一版的文字内容（blocks）
final articlePageProvider =
    FutureProvider.family<ArticlePage, ({String date, int no})>((ref, key) async {
  final raw = await ref
      .watch(engineProvider)
      .call('article.page', {'date': key.date, 'pageNo': key.no});
  return ArticlePage.fromJson(raw is Map<String, dynamic> ? raw : const {});
});

DateTime _dateOnly(DateTime value) => DateTime(value.year, value.month, value.day);

String isoDate(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';

String isoMonth(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}';
