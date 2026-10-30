import 'models.dart';

class ZaobaoItem {
  const ZaobaoItem({
    required this.id,
    required this.title,
    required this.url,
    this.timeLabel,
    this.read = false,
    this.cached = false,
    this.thumbnail,
    this.publishedAt,
  });

  final String id;
  final String title;
  final String url;
  final String? timeLabel;
  final bool read;
  final bool cached;
  final String? thumbnail;
  final String? publishedAt;

  ZaobaoItem markRead() => ZaobaoItem(
    id: id,
    title: title,
    url: url,
    timeLabel: timeLabel,
    thumbnail: thumbnail,
    publishedAt: publishedAt,
    read: true,
    cached: true,
  );

  factory ZaobaoItem.fromJson(Map<String, dynamic> json) => ZaobaoItem(
    id: json['articleId'] as String,
    title: json['title'] as String,
    url: json['url'] as String,
    timeLabel: json['timeLabel'] as String?,
    read: json['read'] == true,
    cached: json['cached'] == true,
    thumbnail: json['thumbnail'] as String?,
    publishedAt: json['publishedAt'] as String?,
  );
}

class ZaobaoArticle {
  const ZaobaoArticle({
    required this.article,
    required this.state,
    this.publishedAt,
    this.fetchedAt,
    this.warnings = const [],
  });

  final Article article;
  final String state;
  final String? publishedAt;
  final String? fetchedAt;
  final List<String> warnings;

  factory ZaobaoArticle.fromJson(Map<String, dynamic> json) => ZaobaoArticle(
    article: Article.fromJson(json),
    state: json['contentState'] as String? ?? 'unknown',
    publishedAt: json['publishedAt'] as String?,
    fetchedAt: json['fetchedAt'] as String?,
    warnings: (json['warnings'] as List<dynamic>? ?? []).cast<String>(),
  );
}
