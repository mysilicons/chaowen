import 'package:flutter/material.dart';

import 'theme/tokens.dart';

/// 应用外壳。P0 阶段只验证：窗口能起、字体能加载、主题能生效。
class RmrbApp extends StatelessWidget {
  const RmrbApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '人民日报 阅报器',
      debugShowCheckedModeBanner: false,
      theme: buildLightTheme(),
      home: const _ShellPage(),
    );
  }
}

class _ShellPage extends StatelessWidget {
  const _ShellPage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '人民日报',
                style: TextStyle(
                  fontFamily: AppFonts.serif,
                  fontSize: 40,
                  fontWeight: FontWeight.w700,
                  color: AppColors.brand,
                  letterSpacing: 4,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '阅报器 · 骨架已就绪',
                style: TextStyle(
                  fontFamily: AppFonts.serif,
                  fontSize: 15,
                  color: AppColors.text2,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 28),
              const Divider(color: AppColors.border),
              const SizedBox(height: 20),
              const Text(
                '　　这是一个能“翻、看、存”的桌面阅报器。当前处于工程准备阶段：'
                '窗口、主题、宋体子集已接通，下一步接入引擎与书架。',
                style: TextStyle(
                  fontFamily: AppFonts.serif,
                  fontSize: 17,
                  height: 1.9,
                  color: AppColors.text,
                ),
              ),
              const SizedBox(height: 32),
              Row(
                children: [
                  FilledButton(
                    onPressed: () {},
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.brand,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 18),
                    ),
                    child: const Text('开始阅读'),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton(
                    onPressed: () {},
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.text2,
                      side: const BorderSide(color: AppColors.border),
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
                    ),
                    child: const Text('下载中心'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
