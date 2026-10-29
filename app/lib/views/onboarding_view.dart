import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/providers.dart';
import '../theme/palette.dart';

/// 首次启动向导：选下载目录、讲清低速策略，之后不再打扰。
class OnboardingView extends ConsumerStatefulWidget {
  const OnboardingView({super.key, required this.onDone});

  final VoidCallback onDone;

  @override
  ConsumerState<OnboardingView> createState() => _OnboardingViewState();
}

class _OnboardingViewState extends ConsumerState<OnboardingView> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final dir = ref.watch(helloProvider).value?['library'] as String?;

    return Scaffold(
      backgroundColor: c.paper,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '人民日报',
                style: TextStyle(
                  fontFamily: AppFonts.serif,
                  fontFamilyFallback: AppFonts.fallback,
                  fontSize: 40,
                  fontWeight: FontWeight.w700,
                  color: c.brand,
                  letterSpacing: 6,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '朝 闻 · 第一次使用',
                style: TextStyle(
                  fontFamily: AppFonts.serif,
                  fontFamilyFallback: AppFonts.fallback,
                  fontSize: 13,
                  color: c.text2,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 30),
              _point(c, Icons.folder_outlined, '文件存在你自己选的目录里',
                  '默认放在「文档 / 人民日报」，按年、按日分文件夹，一份合并好的 PDF + 一份清单。'),
              _point(c, Icons.speed, '只做个人存档，慢速访问',
                  '1 并发、每秒 2 个请求，且不提供"极速"模式——这是为了不给站点添负担。'),
              _point(c, Icons.auto_awesome_outlined, '下载即合成整期，单版自动清理',
                  '每期 20 个版合并成一个带书签的 PDF，约 60 MB。'),
              const SizedBox(height: 26),
              Container(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                decoration: BoxDecoration(
                  color: c.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: c.border),
                ),
                child: Row(
                  children: [
                    Icon(Icons.folder_open, size: 18, color: c.text2),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        dir ?? '读取中…',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: c.text),
                      ),
                    ),
                    TextButton(
                      onPressed: _busy ? null : _pickDir,
                      child: const Text('更改…', style: TextStyle(fontSize: 12)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '继续使用即表示同意：仅供个人学习研究，不得商业使用或对外分发。',
                      style: TextStyle(fontSize: 11, height: 1.6, color: c.text2),
                    ),
                  ),
                  const SizedBox(width: 16),
                  FilledButton(
                    onPressed: _busy ? null : _finish,
                    style: FilledButton.styleFrom(
                      backgroundColor: c.brand,
                      padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 16),
                    ),
                    child: _busy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('开始使用'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _point(AppPalette c, IconData icon, String title, String body) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: c.brand.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 17, color: c.brand),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: c.text,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: TextStyle(fontSize: 12, height: 1.7, color: c.text2),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickDir() async {
    final current = ref.read(helloProvider).value?['library'] as String?;
    final picked = await getDirectoryPath(
      initialDirectory: current,
      confirmButtonText: '用这个目录',
    );
    if (picked == null || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(engineProvider).call('settings.set', {'downloadDir': picked});
      ref.invalidate(helloProvider);
      ref.invalidate(issueProvider);
      ref.invalidate(monthStatusProvider);
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text('目录不可用：$error')));
    }
  }

  Future<void> _finish() async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(engineProvider).call('settings.set', {'onboarded': true});
      ref.invalidate(settingsProvider);
      widget.onDone();
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text('保存失败：$error')));
      if (mounted) setState(() => _busy = false);
    }
  }
}
