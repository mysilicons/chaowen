import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/engine_client.dart';
import 'core/models.dart';
import 'theme/tokens.dart';
import 'views/downloads_view.dart';
import 'views/library_view.dart';

class RmrbApp extends StatelessWidget {
  const RmrbApp({super.key, required this.engine});

  final EngineClient engine;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '人民日报 阅报器',
      debugShowCheckedModeBanner: false,
      theme: buildLightTheme(),
      home: BootstrapGate(engine: engine),
    );
  }
}

/// 启动门：引擎就绪前显示启动画面，失败时给出可操作的重试。
class BootstrapGate extends StatefulWidget {
  const BootstrapGate({super.key, required this.engine});

  final EngineClient engine;

  @override
  State<BootstrapGate> createState() => _BootstrapGateState();
}

class _BootstrapGateState extends State<BootstrapGate> {
  @override
  void initState() {
    super.initState();
    widget.engine.status.addListener(_onStatusChanged);
    if (widget.engine.status.value != EngineState.ready) {
      _bootstrap();
    }
  }

  @override
  void dispose() {
    widget.engine.status.removeListener(_onStatusChanged);
    super.dispose();
  }

  void _onStatusChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _bootstrap() async {
    try {
      await widget.engine.start();
    } catch (_) {
      // 具体错误已经写进 engine.lastError，由界面展示
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = widget.engine.status.value;

    if (status == EngineState.ready) {
      return const HomeShell();
    }
    if (status == EngineState.failed || status == EngineState.crashed) {
      return _Splash(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 36, color: AppColors.brandHover),
            const SizedBox(height: 14),
            const Text(
              '引擎启动失败',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: 460,
              child: Text(
                widget.engine.lastError ?? '未知错误',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, color: AppColors.text2),
              ),
            ),
            const SizedBox(height: 18),
            FilledButton(
              onPressed: _bootstrap,
              style: FilledButton.styleFrom(backgroundColor: AppColors.brand),
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }

    return const _Splash(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(height: 16),
          Text('正在启动引擎…', style: TextStyle(fontSize: 13, color: AppColors.text2)),
        ],
      ),
    );
  }
}

class _Splash extends StatelessWidget {
  const _Splash({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              '人民日报',
              style: TextStyle(
                fontFamily: AppFonts.serif,
                fontSize: 34,
                fontWeight: FontWeight.w700,
                color: AppColors.brand,
                letterSpacing: 4,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              '阅报器',
              style: TextStyle(
                fontFamily: AppFonts.serif,
                fontSize: 13,
                color: AppColors.text2,
                letterSpacing: 6,
              ),
            ),
            const SizedBox(height: 40),
            child,
          ],
        ),
      ),
    );
  }
}

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Sidebar(
            index: _index,
            onSelect: (value) => setState(() => _index = value),
          ),
          const VerticalDivider(width: 1, color: AppColors.border),
          Expanded(
            child: IndexedStack(
              index: _index,
              children: const [LibraryView(), DownloadsView()],
            ),
          ),
        ],
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.index, required this.onSelect});

  final int index;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 214,
      color: AppColors.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(22, 26, 22, 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '人民日报',
                  style: TextStyle(
                    fontFamily: AppFonts.serif,
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: AppColors.brand,
                    letterSpacing: 2,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  '阅 报 器',
                  style: TextStyle(
                    fontFamily: AppFonts.serif,
                    fontSize: 11,
                    color: AppColors.text2,
                    letterSpacing: 2,
                  ),
                ),
              ],
            ),
          ),
          _NavItem(
            icon: Icons.menu_book_outlined,
            label: '书架',
            selected: index == 0,
            onTap: () => onSelect(0),
          ),
          _NavItem(
            icon: Icons.download_outlined,
            label: '下载中心',
            selected: index == 1,
            onTap: () => onSelect(1),
          ),
          const Spacer(),
          const Padding(
            padding: EdgeInsets.fromLTRB(22, 0, 22, 20),
            child: Text(
              '个人存档 · 低速访问\n仅限学习研究使用',
              style: TextStyle(fontSize: 11, height: 1.6, color: AppColors.text2),
            ),
          ),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: selected ? AppColors.brand.withValues(alpha: 0.08) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: selected ? AppColors.brand : AppColors.text2),
            const SizedBox(width: 10),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                color: selected ? AppColors.brand : AppColors.text,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
