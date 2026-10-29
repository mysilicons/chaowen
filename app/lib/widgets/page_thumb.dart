import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models.dart';
import '../state/providers.dart';
import '../theme/tokens.dart';

/// 版面缩略图卡片：图上、版号角标。
class PageThumb extends ConsumerWidget {
  const PageThumb({
    super.key,
    required this.date,
    required this.page,
    this.onTap,
    this.state,
  });

  final String date;
  final PageInfo page;
  final VoidCallback? onTap;
  final DayState? state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
                  _image(ref),
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

  Widget _image(WidgetRef ref) {
    final local = page.thumbLocal;
    if (local != null && File(local).existsSync()) {
      return Image.file(
        File(local),
        fit: BoxFit.cover,
        errorBuilder: (context, error, stack) => const _ThumbPlaceholder(),
      );
    }
    final direct = page.thumbUrl;
    final String? url;
    if (direct != null && direct.isNotEmpty) {
      url = direct;
    } else {
      // 未下载的日期只有 01 版带图；其余按需抓一次并写进库
      url = ref.watch(pageDetailProvider((date: date, no: page.no))).value?.thumbUrl;
    }
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
