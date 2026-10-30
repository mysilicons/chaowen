import 'dart:io';

import 'package:flutter/material.dart';

import '../core/models.dart';
import '../theme/palette.dart';

/// Rendering only: fetching, navigation and source policy stay with the caller.
class ArticleBody extends StatelessWidget {
  const ArticleBody({
    super.key,
    required this.article,
    required this.scale,
    this.controller,
    this.metadata,
    this.leading,
    this.missingImagePlaceholder = false,
    this.remoteImages = false,
  });

  final Article article;
  final double scale;
  final ScrollController? controller;
  final String? metadata;
  final Widget? leading;
  final bool missingImagePlaceholder;
  final bool remoteImages;

  @override
  Widget build(BuildContext context) => SelectionArea(
    child: SingleChildScrollView(
      controller: controller,
      padding: const EdgeInsets.fromLTRB(28, 26, 28, 32),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 980),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ?leading,
              Text(
                article.title,
                style: TextStyle(
                  fontFamily: AppFonts.serif,
                  fontFamilyFallback: AppFonts.fallback,
                  fontSize: 22 * scale,
                  fontWeight: FontWeight.w700,
                  height: 1.5,
                  color: context.colors.text,
                ),
              ),
              if (article.author case final author? when author.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  author,
                  style: TextStyle(
                    fontSize: 12 * scale,
                    color: context.colors.text2,
                  ),
                ),
              ],
              if (metadata != null) ...[
                const SizedBox(height: 8),
                Text(
                  metadata!,
                  style: TextStyle(
                    fontSize: 12 * scale,
                    color: context.colors.text2,
                  ),
                ),
              ],
              const SizedBox(height: 20),
              for (final block in article.blocks)
                if (block.isImage)
                  _image(context, block)
                else if ((block.text ?? '').isNotEmpty)
                  Padding(
                    padding: EdgeInsets.only(bottom: 14 * scale),
                    child: Text(
                      '\u3000\u3000${block.text}',
                      style: TextStyle(
                        fontFamily: AppFonts.serif,
                        fontFamilyFallback: AppFonts.fallback,
                        fontSize: 17 * scale,
                        height: 1.9,
                        color: context.colors.text,
                      ),
                    ),
                  ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _image(BuildContext context, Block block) {
    final path = block.local;
    final exists = path != null && File(path).existsSync();
    if (!exists && !missingImagePlaceholder) return const SizedBox.shrink();
    final placeholder = Container(
      height: 72,
      alignment: Alignment.center,
      color: context.colors.surface,
      child: Text('图片尚未缓存或暂不可用', style: TextStyle(color: context.colors.text2)),
    );
    return Padding(
      padding: EdgeInsets.only(bottom: 16 * scale),
      child: Column(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: exists
                ? Image.file(
                    File(path),
                    fit: BoxFit.fitWidth,
                    cacheWidth: 1600,
                    errorBuilder: (context, error, stack) => placeholder,
                  )
                : remoteImages && block.src != null
                ? Image.network(
                    block.src!,
                    fit: BoxFit.fitWidth,
                    cacheWidth: 1600,
                    errorBuilder: (context, error, stack) => placeholder,
                  )
                : placeholder,
          ),
          if ((block.caption ?? '').isNotEmpty) ...[
            const SizedBox(height: 7),
            Text(
              block.caption!,
              style: TextStyle(
                fontSize: 12 * scale,
                height: 1.5,
                color: context.colors.text2,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
