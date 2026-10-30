import 'models.dart';

class ZaobaoItem {
  const ZaobaoItem({
    required this.id,
    required this.title,
    required this.url,
    this.timeLabel,
    this.read = false,
    this.cached = false,
  });

  final String id;
  final String title;
  final String url;
  final String? timeLabel;
  final bool read;
  final bool cached;

  factory ZaobaoItem.fromJson(Map<String, dynamic> json) => ZaobaoItem(
    id: json['articleId'] as String,
    title: json['title'] as String,
    url: json['url'] as String,
    timeLabel: json['timeLabel'] as String?,
    read: json['read'] == true,
    cached: json['cached'] == true,
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
