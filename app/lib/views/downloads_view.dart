import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/providers.dart';
import '../theme/palette.dart';

class DownloadsView extends ConsumerStatefulWidget {
  const DownloadsView({super.key});

  @override
  ConsumerState<DownloadsView> createState() => _DownloadsViewState();
}

class _DownloadsViewState extends ConsumerState<DownloadsView> {
  late DateTime _from;
  late DateTime _to;
  late DateTime _single;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _to = DateTime(now.year, now.month, now.day);
    _single = _to;
    _from = _to.subtract(const Duration(days: 6));
  }

  int get _days => _to.difference(_from).inDays + 1;

  @override
  Widget build(BuildContext context) {
    final jobs = ref.watch(queueProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Text(
                '下载中心',
                style: TextStyle(
                  fontFamily: AppFonts.serif,
                  fontFamilyFallback: AppFonts.fallback,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(child: _LibraryPath()),
              TextButton.icon(
                onPressed: () => _reveal(),
                icon: const Icon(Icons.folder_open, size: 16),
                label: const Text('打开下载目录', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('单日下载', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 10),
                Row(
                  children: [
                    _dateField('日期', _single, (value) => setState(() => _single = value)),
                    const SizedBox(width: 12),
                    Text(
                      '${_single.year}年${_single.month}月${_single.day}日',
                      style: TextStyle(fontSize: 12, color: context.colors.text2),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Icon(Icons.speed, size: 16, color: context.colors.text2),
                    const SizedBox(width: 6),
                    Text(
                      '低速模式：1 并发 · 1 秒间隔（硬性上限 2）',
                      style: TextStyle(fontSize: 12, color: context.colors.text2),
                    ),
                    const Spacer(),
                    FilledButton(
                      onPressed: () => _startSingle(context, isoDate(_single)),
                      style: FilledButton.styleFrom(backgroundColor: context.colors.brand),
                      child: const Text('开始下载'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('批量下载', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _preset('近 7 天', 7),
                    _preset('近 30 天', 30),
                    _preset('本月', -1),
                    _preset('本年', -2),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    _dateField('从', _from, (value) => setState(() => _from = value)),
                    const SizedBox(width: 12),
                    _dateField('到', _to, (value) => setState(() => _to = value)),
                    const SizedBox(width: 20),
                    Expanded(
                      child: Text(
                        '$_days 天 · 约 ${(_days * 63)} MB · 约 ${(_days * 45 / 60).ceil()} 分钟',
                        style: TextStyle(fontSize: 12, color: context.colors.text2),
                      ),
                    ),
                    FilledButton(
                      onPressed: _days > 0 ? () => _startBatch(context) : null,
                      style: FilledButton.styleFrom(backgroundColor: context.colors.brand),
                      child: const Text('加入队列'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              const Text('队列', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(width: 8),
              Text('${jobs.length}', style: TextStyle(color: context.colors.text2)),
              const Spacer(),
              TextButton(
                onPressed: () => ref.read(queueProvider.notifier).clearFinished(),
                child: const Text('清空已完成'),
              ),
            ],
          ),
          const SizedBox(height: 4),
          if (jobs.isEmpty)
            Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(
                child: Text('暂无任务', style: TextStyle(color: context.colors.text2)),
              ),
            )
          else
            ...jobs.map(
              (job) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _JobTile(job: job),
              ),
            ),
        ],
      ),
    );
  }

  Widget _preset(String label, int days) {
    final c = context.colors;
    return ActionChip(
      label: Text(label, style: TextStyle(fontSize: 12, color: c.text)),
      labelStyle: TextStyle(fontSize: 12, color: c.text),
      onPressed: () {
        final now = DateTime.now();
        setState(() {
          _to = DateTime(now.year, now.month, now.day);
          _from = switch (days) {
            7 => _to.subtract(const Duration(days: 6)),
            30 => _to.subtract(const Duration(days: 29)),
            -1 => DateTime(now.year, now.month, 1),
            _ => DateTime(now.year, 1, 1),
          };
        });
      },
      backgroundColor: const Color(0xFFF6F3EC),
      side: BorderSide(color: context.colors.border),
    );
  }

  Widget _dateField(String label, DateTime value, ValueChanged<DateTime> onChanged) {
    return InkWell(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: value,
          firstDate: DateTime(2024, 12, 1),
          lastDate: DateTime.now(),
        );
        if (picked != null) onChanged(picked);
      },
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          border: Border.all(color: context.colors.border),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('$label ', style: TextStyle(fontSize: 12, color: context.colors.text2)),
            Text(isoDate(value), style: const TextStyle(fontSize: 13)),
          ],
        ),
      ),
    );
  }

  Future<void> _reveal() async {
    final messenger = ScaffoldMessenger.of(context);
    final hello = await ref.read(helloProvider.future);
    final library = hello['library'] as String?;
    if (library == null) {
      messenger.showSnackBar(const SnackBar(content: Text('引擎未就绪')));
      return;
    }
    try {
      await ref.read(engineProvider).call('storage.reveal', {'path': library});
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text('打开失败：$error')));
    }
  }

  Future<void> _startSingle(BuildContext context, String date) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(engineProvider).call('download.start', {'date': date});
      messenger.showSnackBar(const SnackBar(content: Text('任务已提交')));
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text('提交失败：$error')));
    }
  }

  Future<void> _startBatch(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final raw = await ref.read(engineProvider).call('batch.start', {
        'from': isoDate(_from),
        'to': isoDate(_to),
      });
      final jobId = raw is Map<String, dynamic> ? raw['jobId'] : null;
      messenger.showSnackBar(
        SnackBar(content: Text('已加入队列：$_days 天${jobId == null ? '' : '（$jobId）'}')),
      );
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text('提交失败：$error')));
    }
  }
}

class _JobTile extends ConsumerWidget {
  const _JobTile({required this.job});

  final DownloadJob job;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final failed = job.status == 'failed';
    final finished = job.status == 'finished' || job.status == 'archived';

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(job.date, style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(width: 10),
              Text(
                failed
                    ? '失败'
                    : finished
                    ? '完成'
                    : '${job.currentPage > 0 ? '第 ${job.currentPage} 版 · ' : ''}'
                          '${job.done}/${job.total}',
                style: TextStyle(
                  fontSize: 12,
                  color: failed
                      ? context.colors.brandHover
                      : finished
                      ? context.colors.success
                      : context.colors.text2,
                ),
              ),
              const Spacer(),
              if (job.error != null)
                Text(
                  job.error!,
                  style: TextStyle(fontSize: 11, color: context.colors.brandHover),
                ),
              if (job.status == 'running' || job.status == 'paused' || job.status == 'queued') ...[
                TextButton(
                  onPressed: () => _pause(context, ref),
                  style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                  child: Text(job.paused ? '继续' : '暂停',
                      style: const TextStyle(fontSize: 12)),
                ),
                TextButton(
                  onPressed: () => _cancel(context, ref),
                  style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                  child: Text('取消',
                      style: TextStyle(fontSize: 12, color: context.colors.brandHover)),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: job.progress,
              minHeight: 5,
              backgroundColor: context.colors.border,
              valueColor: AlwaysStoppedAnimation(
                failed ? context.colors.brandHover : context.colors.brand,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pause(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final notifier = ref.read(queueProvider.notifier);
    final next = !job.paused;
    try {
      await ref.read(engineProvider).call(
        next ? 'download.pause' : 'download.resume',
        {'jobId': job.jobId},
      );
      notifier.markPaused(job.jobId, next);
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text('操作失败：$error')));
    }
  }

  Future<void> _cancel(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(engineProvider).call('download.cancel', {'jobId': job.jobId});
      messenger.showSnackBar(const SnackBar(content: Text('已取消')));
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text('取消失败：$error')));
    }
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: context.colors.border),
      ),
      child: child,
    );
  }
}


class _LibraryPath extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hello = ref.watch(helloProvider);
    final path = hello.value?['library'] as String?;
    return Text(
      path == null ? '' : '下载到：$path',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(fontSize: 11, color: context.colors.text2),
    );
  }
}
