import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/providers.dart';
import '../theme/palette.dart';

/// The same quiet type controls on both newspaper and web article toolbars.
class ReaderFontControls extends ConsumerWidget {
  const ReaderFontControls({super.key, required this.scale});
  final double scale;

  @override
  Widget build(BuildContext context, WidgetRef ref) => SizedBox(
    width: 132,
    child: Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        ReaderTextAction(
          label: 'A-',
          tooltip: '缩小字号',
          onPressed: scale > .85
              ? () => ref.read(readerScaleProvider.notifier).step(-.1)
              : null,
        ),
        ReaderTextAction(
          label: 'A+',
          tooltip: '放大字号',
          onPressed: scale < 1.5
              ? () => ref.read(readerScaleProvider.notifier).step(.1)
              : null,
        ),
        const SizedBox(width: 6),
        Text(
          '${(scale * 100).round()}%',
          style: TextStyle(fontSize: 11, color: context.colors.text2),
        ),
      ],
    ),
  );
}

class ReaderTextAction extends StatelessWidget {
  const ReaderTextAction({
    super.key,
    required this.label,
    required this.onPressed,
    this.tooltip,
    this.icon,
  });
  final String label;
  final String? tooltip;
  final IconData? icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip ?? label,
    child: InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(4),
      hoverColor: context.colors.border.withValues(alpha: .4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 14, color: context.colors.text2),
              const SizedBox(width: 5),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: onPressed == null
                    ? context.colors.text2.withValues(alpha: .4)
                    : context.colors.text2,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
