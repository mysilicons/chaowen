import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/providers.dart';
import '../theme/tokens.dart';

class DownloadsView extends ConsumerWidget {
  const DownloadsView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final jobs = ref.watch(queueProvider);
    final date = ref.watch(selectedDateProvider);

    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            '下载中心',
            style: TextStyle(
              fontFamily: AppFonts.serif,
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 18),
          _Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('单日下载', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Text(
                  '${date.year}年${date.month}月${date.day}日',
                  style: const TextStyle(fontSize: 13, color: AppColors.text2),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    const Icon(Icons.speed, size: 16, color: AppColors.text2),
                    const SizedBox(width: 6),
                    const Text(
                      '低速模式：1 并发 · 1 秒间隔（硬性上限 2）',
                      style: TextStyle(fontSize: 12, color: AppColors.text2),
                    ),
                    const Spacer(),
                    FilledButton(
                      onPressed: () => _start(context, ref, isoDate(date)),
                      style: FilledButton.styleFrom(backgroundColor: AppColors.brand),
                      child: const Text('开始下载'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              const Text('队列', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(width: 8),
              Text('${jobs.length}', style: const TextStyle(color: AppColors.text2)),
              const Spacer(),
              TextButton(
                onPressed: () => ref.read(queueProvider.notifier).clearFinished(),
                child: const Text('清空已完成'),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Expanded(
            child: jobs.isEmpty
                ? const Center(
                    child: Text('暂无任务', style: TextStyle(color: AppColors.text2)),
                  )
                : ListView.separated(
                    itemCount: jobs.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, index) => _JobTile(job: jobs[index]),
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _start(BuildContext context, WidgetRef ref, String date) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(engineProvider).call('download.start', {'date': date});
      messenger.showSnackBar(const SnackBar(content: Text('任务已提交')));
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text('提交失败：$error')));
    }
  }
}

class _JobTile extends StatelessWidget {
  const _JobTile({required this.job});

  final DownloadJob job;

  @override
  Widget build(BuildContext context) {
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
                    : '第 ${job.currentPage} 版 · ${job.done}/${job.total}',
                style: TextStyle(
                  fontSize: 12,
                  color: failed
                      ? AppColors.brandHover
                      : finished
                      ? AppColors.success
                      : AppColors.text2,
                ),
              ),
              const Spacer(),
              if (job.error != null)
                Text(
                  job.error!,
                  style: const TextStyle(fontSize: 11, color: AppColors.brandHover),
                ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: job.progress,
              minHeight: 5,
              backgroundColor: AppColors.border,
              valueColor: AlwaysStoppedAnimation(
                failed ? AppColors.brandHover : AppColors.brand,
              ),
            ),
          ),
        ],
      ),
    );
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
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: child,
    );
  }
}
