import 'package:flutter/material.dart';

import '../core/models.dart';
import '../theme/tokens.dart';

/// 版面缩略图卡片：图上、版号角标。
class PageThumb extends StatelessWidget {
  const PageThumb({super.key, required this.page, this.onTap, this.state});

  final PageInfo page;
  final VoidCallback? onTap;
  final DayState? state;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _image(),
                  Positioned(
                    left: 0,
                    top: 0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                      color: Colors.black.withValues(alpha: 0.55),
                      child: Text(
                        page.no.toString().padLeft(2, '0'),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ),
                  if (state == DayState.archived)
                    const Positioned(
                      right: 4,
                      top: 4,
                      child: Icon(Icons.check_circle, size: 14, color: Colors.white),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            page.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, color: AppColors.text2),
          ),
        ],
      ),
    );
  }

  Widget _image() {
    final url = page.thumbUrl;
    if (url == null || url.isEmpty) return const _ThumbPlaceholder();
    return Image.network(
      url,
      fit: BoxFit.cover,
      loadingBuilder: (context, child, progress) =>
          progress == null ? child : const _ThumbPlaceholder(),
      errorBuilder: (context, error, stack) => const _ThumbPlaceholder(),
    );
  }
}

class _ThumbPlaceholder extends StatelessWidget {
  const _ThumbPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF1EEE7),
      alignment: Alignment.center,
      child: const Icon(Icons.article_outlined, size: 20, color: AppColors.text2),
    );
  }
}
