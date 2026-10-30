import 'package:flutter/material.dart';

import '../core/zaobao_models.dart';
import '../theme/palette.dart';

/// Newspaper-like editorial hierarchy on paper, without Material card chrome.
class ZaobaoFeed extends StatelessWidget {
  const ZaobaoFeed({
    super.key,
    required this.items,
    required this.controller,
    required this.onOpen,
    required this.footer,
  });
  final List<ZaobaoItem> items;
  final ScrollController controller;
  final ValueChanged<ZaobaoItem> onOpen;
  final Widget footer;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, bounds) {
      final columns = bounds.maxWidth >= 1000 ? 3 : 2;
      final headlineColumns = items.length.clamp(0, 3);
      // A text-only lead shares its column with another story rather than leaving
      // an image-sized hole beside the illustrated leads.
      final stackedLead =
          items.length > 3 &&
          items.first.thumbnail == null &&
          items.skip(1).take(2).any((item) => item.thumbnail != null);
      final leadCount = stackedLead ? 4 : headlineColumns;
      final remaining = items.length - leadCount;
      return Scrollbar(
        controller: controller,
        child: CustomScrollView(
          controller: controller,
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 14),
              sliver: SliverToBoxAdapter(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '中国频道',
                      style: TextStyle(
                        fontFamily: AppFonts.serif,
                        fontFamilyFallback: AppFonts.fallback,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: context.colors.text,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      '中国时事 · 纵览与观察',
                      style: TextStyle(
                        fontSize: 11,
                        color: context.colors.text2,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${items.length} 篇',
                      style: TextStyle(
                        fontSize: 11,
                        color: context.colors.text2,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (leadCount > 0)
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                sliver: SliverToBoxAdapter(
                  child: IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var i = 0; i < headlineColumns; i++) ...[
                          if (i > 0)
                            VerticalDivider(
                              width: 36,
                              thickness: 1,
                              color: context.colors.border,
                            ),
                          Expanded(
                            flex: i == 0 ? 5 : 4,
                            child: stackedLead && i == 0
                                ? Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      _Lead(
                                        item: items[0],
                                        number: 1,
                                        primary: true,
                                        onTap: () => onOpen(items[0]),
                                      ),
                                      const SizedBox(height: 20),
                                      _Entry(
                                        item: items[3],
                                        number: 4,
                                        onTap: () => onOpen(items[3]),
                                      ),
                                    ],
                                  )
                                : _Lead(
                                    item: items[i],
                                    number: i + 1,
                                    primary: i == 0,
                                    onTap: () => onOpen(items[i]),
                                  ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(24, 18, 24, 0),
              sliver: SliverToBoxAdapter(
                child: Divider(height: 1, color: context.colors.border),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 0),
              sliver: SliverList.builder(
                itemCount: (remaining / columns).ceil(),
                itemBuilder: (context, row) => IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var column = 0; column < columns; column++) ...[
                        if (column > 0)
                          VerticalDivider(
                            width: 32,
                            thickness: 1,
                            color: context.colors.border,
                          ),
                        Expanded(
                          child:
                              leadCount + row * columns + column < items.length
                              ? _Entry(
                                  item:
                                      items[leadCount + row * columns + column],
                                  number:
                                      leadCount + row * columns + column + 1,
                                  onTap: () => onOpen(
                                    items[leadCount + row * columns + column],
                                  ),
                                )
                              : const SizedBox.shrink(),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(24, 18, 24, 28),
              sliver: SliverToBoxAdapter(child: footer),
            ),
          ],
        ),
      );
    },
  );
}

class _Lead extends StatelessWidget {
  const _Lead({
    required this.item,
    required this.number,
    required this.primary,
    required this.onTap,
  });
  final ZaobaoItem item;
  final int number;
  final bool primary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(4),
    hoverColor: context.colors.border.withValues(alpha: .25),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (item.thumbnail != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 13),
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: Image.network(
                  item.thumbnail!,
                  fit: BoxFit.cover,
                  cacheWidth: 640,
                  errorBuilder: (context, error, stack) => Container(
                    color: context.colors.border.withValues(alpha: .3),
                    alignment: Alignment.center,
                    child: Icon(
                      Icons.landscape_outlined,
                      color: context.colors.text2,
                      size: 24,
                    ),
                  ),
                ),
              ),
            ),
          ),
        _Meta(item: item, number: number),
        const SizedBox(height: 9),
        Text(
          item.title,
          maxLines: 4,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontFamily: AppFonts.serif,
            fontFamilyFallback: AppFonts.fallback,
            fontSize: primary ? 24 : 20,
            height: 1.5,
            fontWeight: FontWeight.w700,
            color: context.colors.text,
          ),
        ),
        if ((item.excerpt ?? '').isNotEmpty) ...[
          const SizedBox(height: 9),
          Text(
            item.excerpt!,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              height: 1.8,
              color: context.colors.text2,
            ),
          ),
        ],
      ],
    ),
  );
}

class _Entry extends StatelessWidget {
  const _Entry({required this.item, required this.number, required this.onTap});
  final ZaobaoItem item;
  final int number;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    hoverColor: context.colors.border.withValues(alpha: .25),
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 18),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: context.colors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Meta(item: item, number: number),
          const SizedBox(height: 9),
          Text(
            item.title,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: AppFonts.serif,
              fontFamilyFallback: AppFonts.fallback,
              fontSize: 17,
              height: 1.65,
              color: context.colors.text,
              fontWeight: item.read ? FontWeight.w400 : FontWeight.w600,
            ),
          ),
          if ((item.excerpt ?? '').isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              item.excerpt!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                height: 1.7,
                color: context.colors.text2,
              ),
            ),
          ],
        ],
      ),
    ),
  );
}

class _Meta extends StatelessWidget {
  const _Meta({required this.item, required this.number});
  final ZaobaoItem item;
  final int number;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Text(
        number.toString().padLeft(2, '0'),
        style: TextStyle(
          fontSize: 10,
          fontFeatures: const [FontFeature.tabularFigures()],
          color: item.read ? context.colors.text2 : context.colors.brand,
        ),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          _time(item.timeLabel ?? item.publishedAt),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 10, color: context.colors.text2),
        ),
      ),
      if (item.read)
        Text('已读', style: TextStyle(fontSize: 10, color: context.colors.text2)),
      if (item.cached)
        Padding(
          padding: const EdgeInsets.only(left: 6),
          child: Icon(
            Icons.offline_pin_outlined,
            size: 11,
            color: context.colors.text2,
          ),
        ),
    ],
  );

  String _time(String? value) {
    if (value == null) return '中国';
    final parsed = DateTime.tryParse(value);
    if (parsed == null) return value;
    final date = parsed.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(date.month)}月${two(date.day)}日 ${two(date.hour)}:${two(date.minute)}';
  }
}
