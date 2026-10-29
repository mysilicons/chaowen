import 'package:flutter/material.dart';

/// 设计令牌：颜色。
abstract final class AppColors {
  static const brand = Color(0xFFC8102E);
  static const brandHover = Color(0xFFA50D26);
  static const paper = Color(0xFFFBFAF7);
  static const surface = Color(0xFFFFFFFF);
  static const border = Color(0xFFE7E3DA);
  static const text = Color(0xFF1C1B19);
  static const text2 = Color(0xFF6E6A63);
  static const gold = Color(0xFFB08D57);
  static const success = Color(0xFF2F7D5B);
}

/// 设计令牌：字体族。
abstract final class AppFonts {
  /// 思源宋体完整字库（静态 400/700，6.5 万字形），用于报头、标题与正文。
  static const serif = 'SourceHanSerifSC';

  /// 兜底链：完整字库已覆盖 CJK，这里只处理极少数缺字与西文符号。
  /// 顺序按平台常见字体排，最后落到系统 UI 字体。
  static const fallback = <String>[
    'Microsoft YaHei',
    'PingFang SC',
    'Noto Sans CJK SC',
    'Segoe UI',
  ];
}

ThemeData buildLightTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.brand,
    surface: AppColors.surface,
  );

  return ThemeData(
    useMaterial3: true,
    fontFamilyFallback: AppFonts.fallback,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.paper,
    dividerColor: AppColors.border,
    visualDensity: VisualDensity.standard,
  );
}
