import 'package:flutter/material.dart';

/// 设计令牌：颜色。
///
/// 用 [ThemeExtension] 而不是全局常量，是为了让深色/浅色能在运行时切换：
/// 组件通过 `context.colors.xxx` 取值，切主题时随 Theme 一起重建。
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.brand,
    required this.brandHover,
    required this.paper,
    required this.surface,
    required this.border,
    required this.text,
    required this.text2,
    required this.gold,
    required this.success,
    required this.isDark,
  });

  final Color brand;
  final Color brandHover;
  final Color paper;
  final Color surface;
  final Color border;
  final Color text;
  final Color text2;
  final Color gold;
  final Color success;
  final bool isDark;

  static const light = AppPalette(
    brand: Color(0xFFC8102E),
    brandHover: Color(0xFFA50D26),
    paper: Color(0xFFFBFAF7),
    surface: Color(0xFFFFFFFF),
    border: Color(0xFFE7E3DA),
    text: Color(0xFF1C1B19),
    text2: Color(0xFF6E6A63),
    gold: Color(0xFFB08D57),
    success: Color(0xFF2F7D5B),
    isDark: false,
  );

  static const dark = AppPalette(
    brand: Color(0xFFE23A4E),
    brandHover: Color(0xFFF05568),
    paper: Color(0xFF14161A),
    surface: Color(0xFF1C1F24),
    border: Color(0xFF2C3037),
    text: Color(0xFFEDEAE3),
    text2: Color(0xFF9A958C),
    gold: Color(0xFFC9A46B),
    success: Color(0xFF4CAF82),
    isDark: true,
  );

  @override
  AppPalette copyWith({
    Color? brand,
    Color? brandHover,
    Color? paper,
    Color? surface,
    Color? border,
    Color? text,
    Color? text2,
    Color? gold,
    Color? success,
    bool? isDark,
  }) {
    return AppPalette(
      brand: brand ?? this.brand,
      brandHover: brandHover ?? this.brandHover,
      paper: paper ?? this.paper,
      surface: surface ?? this.surface,
      border: border ?? this.border,
      text: text ?? this.text,
      text2: text2 ?? this.text2,
      gold: gold ?? this.gold,
      success: success ?? this.success,
      isDark: isDark ?? this.isDark,
    );
  }

  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) {
    if (other is! AppPalette) return this;
    return AppPalette(
      brand: Color.lerp(brand, other.brand, t)!,
      brandHover: Color.lerp(brandHover, other.brandHover, t)!,
      paper: Color.lerp(paper, other.paper, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      border: Color.lerp(border, other.border, t)!,
      text: Color.lerp(text, other.text, t)!,
      text2: Color.lerp(text2, other.text2, t)!,
      gold: Color.lerp(gold, other.gold, t)!,
      success: Color.lerp(success, other.success, t)!,
      isDark: t < 0.5 ? isDark : other.isDark,
    );
  }
}

extension AppPaletteContext on BuildContext {
  /// `context.colors.brand`，比 `Theme.of(context).extension<AppPalette>()!` 短
  AppPalette get colors => Theme.of(this).extension<AppPalette>() ?? AppPalette.light;
}

/// 设计令牌：字体族。
abstract final class AppFonts {
  static const serif = 'SourceHanSerifSC';

  static const fallback = <String>[
    'Microsoft YaHei',
    'PingFang SC',
    'Noto Sans CJK SC',
    'Segoe UI',
  ];
}

ThemeData buildTheme(Brightness brightness) {
  final palette = brightness == Brightness.dark ? AppPalette.dark : AppPalette.light;

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    fontFamilyFallback: AppFonts.fallback,
    scaffoldBackgroundColor: palette.paper,
    dividerColor: palette.border,
    colorScheme: ColorScheme.fromSeed(
      seedColor: palette.brand,
      brightness: brightness,
      surface: palette.surface,
    ),
    extensions: [palette],
  );
}
