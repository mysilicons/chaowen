import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/providers.dart';
import '../theme/palette.dart';

/// 设置页：独立视图，替代原来的弹框。
class SettingsView extends ConsumerWidget {
  const SettingsView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hello = ref.watch(helloProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(32, 26, 32, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '设置',
            style: TextStyle(
              fontFamily: AppFonts.serif,
              fontFamilyFallback: AppFonts.fallback,
              fontSize: 24,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 22),
          _Section(
            title: '存储',
            children: [
              _Row(
                label: '下载目录',
                value: hello.value?['library'] as String? ?? '—',
                action: TextButton(
                  onPressed: () => _pickDir(context, ref),
                  child: const Text('更改…', style: TextStyle(fontSize: 12)),
                ),
              ),
              const SizedBox(height: 4),
              _Row(
                label: '缓存目录',
                value: hello.value?['cache'] as String? ?? '—',
                action: TextButton(
                  onPressed: () => _reveal(ref, hello.value?['cache'] as String?),
                  child: const Text('打开', style: TextStyle(fontSize: 12)),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                '切换下载目录不会迁移已有文件；旧目录里的内容需要手动搬过去。',
                style: TextStyle(fontSize: 11, height: 1.6, color: context.colors.text2),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _Section(
            title: '外观',
            children: [
              _SwitchRow(
                label: '深色模式',
                hint: '夜间阅读更省眼，切换即时生效',
                value: ref.watch(darkModeProvider),
                onChanged: (_) => ref.read(darkModeProvider.notifier).toggle(),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _Section(
            title: '阅读',
            children: [
              _SwitchRow(
                label: '打开时进入 PDF',
                hint: '关闭则默认文字模式（PDF 需要先下载本期）',
                value: ref.watch(readerModeProvider) == 'pdf',
                onChanged: (value) => ref
                    .read(readerModeProvider.notifier)
                    .select(value ? 'pdf' : 'text'),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  SizedBox(
                    width: 76,
                    child: Text('正文字号',
                        style: TextStyle(fontSize: 12, color: context.colors.text2)),
                  ),
                  Expanded(
                    child: Slider(
                      value: ref.watch(readerScaleProvider),
                      min: 0.85,
                      max: 1.5,
                      divisions: 13,
                      label: '${(ref.watch(readerScaleProvider) * 100).round()}%',
                      activeColor: context.colors.brand,
                      onChanged: (value) => ref
                          .read(readerScaleProvider.notifier)
                          .step(value - ref.read(readerScaleProvider)),
                    ),
                  ),
                  SizedBox(
                    width: 44,
                    child: Text(
                      '${(ref.watch(readerScaleProvider) * 100).round()}%',
                      textAlign: TextAlign.right,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              _Row(label: '阅读速度', value: '1 并发 · 2 请求/秒（低速访问）'),
            ],
          ),
          const SizedBox(height: 16),
          _Section(
            title: '关于',
            children: [
              _Row(
                label: '版本',
                value:
                    '朝闻 0.1.0 · 引擎 ${hello.value?['engine'] ?? '—'}'
                    '（Python ${hello.value?['python'] ?? '—'}）',
              ),
              _Row(label: '协议', value: 'IPC v${hello.value?['protocol'] ?? '—'}'),
              const SizedBox(height: 10),
              Text(
                '仅供个人学习研究使用，请勿用于商业目的或对外分发。\n'
                '《人民日报》（电子版）版权归人民网股份有限公司所有。',
                style: TextStyle(fontSize: 11, height: 1.7, color: context.colors.text2),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _pickDir(BuildContext context, WidgetRef ref) async {
    final current = ref.read(helloProvider).value?['library'] as String?;
    final picked = await getDirectoryPath(
      initialDirectory: current,
      confirmButtonText: '用这个目录',
    );
    if (picked == null || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(engineProvider).call('settings.set', {'downloadDir': picked});
      ref.invalidate(helloProvider);
      ref.invalidate(issueProvider);
      ref.invalidate(monthStatusProvider);
      messenger.showSnackBar(SnackBar(content: Text('下载目录已切换：$picked')));
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text('切换失败：$error')));
    }
  }

  Future<void> _reveal(WidgetRef ref, String? path) async {
    if (path == null) return;
    try {
      await ref.read(engineProvider).call('storage.reveal', {'path': path});
    } catch (_) {
      // 目录不存在时静默失败，界面上路径仍然可见
    }
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.label,
    required this.hint,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final String hint;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 76,
          child: Text(label, style: TextStyle(fontSize: 12, color: context.colors.text2)),
        ),
        Expanded(
          child: Text(hint, style: TextStyle(fontSize: 11, color: context.colors.text2)),
        ),
        Switch(
          value: value,
          onChanged: onChanged,
          activeThumbColor: Colors.white,
          activeTrackColor: context.colors.brand,
        ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: context.colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: context.colors.text,
            ),
          ),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value, this.action});

  final String label;
  final String value;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 76,
          child: Text(label, style: TextStyle(fontSize: 12, color: context.colors.text2)),
        ),
        Expanded(
          child: SelectableText(
            value,
            style: const TextStyle(fontSize: 12, height: 1.5),
          ),
        ),
        ?action,
      ],
    );
  }
}
