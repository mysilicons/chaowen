/// 协议数据模型：字段名与 docs/ipc.md 严格一致（camelCase）。
library;

int _asInt(Object? value) => value is int ? value : int.tryParse('${value ?? ''}') ?? 0;

String _asString(Object? value) => value is String ? value : '';

String? _asStringOrNull(Object? value) => value is String && value.isNotEmpty ? value : null;

class ArticleRef {
  const ArticleRef({required this.title, required this.url});

  final String title;
  final String url;

  factory ArticleRef.fromJson(Map<String, dynamic> json) => ArticleRef(
    title: _asString(json['title']).trim(),
    url: _asString(json['url']),
  );
}

class PageInfo {
  const PageInfo({
    required this.no,
    required this.title,
    required this.url,
    this.pdfUrl,
    this.thumbUrl,
    this.articles = const [],
  });

  final int no;
  final String title;
  final String url;
  final String? pdfUrl;
  final String? thumbUrl;
  final List<ArticleRef> articles;

  factory PageInfo.fromJson(Map<String, dynamic> json) => PageInfo(
    no: _asInt(json['no']),
    title: _asString(json['title']),
    url: _asString(json['url']),
    pdfUrl: _asStringOrNull(json['pdfUrl']),
    thumbUrl: _asStringOrNull(json['thumbUrl']),
    articles: (json['articles'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(ArticleRef.fromJson)
        .toList(growable: false),
  );
}

class Issue {
  const Issue({this.date, required this.pageCount, this.pages = const []});

  final String? date;
  final int pageCount;
  final List<PageInfo> pages;

  factory Issue.fromJson(Map<String, dynamic> json) => Issue(
    date: _asStringOrNull(json['date']),
    pageCount: _asInt(json['pageCount']),
    pages: (json['pages'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(PageInfo.fromJson)
        .toList(growable: false),
  );
}

enum DayState { absent, archived, partial, downloading, failed }

class DayStatus {
  const DayStatus({required this.date, required this.state, this.bytes = 0, this.pageCount = 0});

  final String date;
  final DayState state;
  final int bytes;
  final int pageCount;

  factory DayStatus.fromJson(Map<String, dynamic> json) {
    final raw = _asString(json['status']);
    final state = switch (raw) {
      'archived' => DayState.archived,
      'partial' => DayState.partial,
      'downloading' => DayState.downloading,
      'failed' => DayState.failed,
      _ => DayState.absent,
    };
    return DayStatus(
      date: _asString(json['date']),
      state: state,
      bytes: _asInt(json['bytes']),
      pageCount: _asInt(json['pageCount']),
    );
  }
}

class EngineEvent {
  const EngineEvent(this.name, this.data);

  final String name;
  final Map<String, dynamic> data;
}

class EngineException implements Exception {
  const EngineException(this.code, this.message, {this.detail});

  final String code;
  final String message;
  final String? detail;

  @override
  String toString() => detail == null ? '$code: $message' : '$code: $message ($detail)';
}

enum EngineState { idle, starting, ready, crashed, failed }


enum PageKind { normal, single, imageOnly, empty, failed }

PageKind _kindFrom(String raw) => switch (raw) {
  'normal' => PageKind.normal,
  'single' => PageKind.single,
  'image_only' => PageKind.imageOnly,
  'empty' => PageKind.empty,
  _ => PageKind.failed,
};

class Block {
  const Block({required this.type, this.text, this.src, this.local, this.caption});

  final String type;
  final String? text;
  final String? src;
  final String? local;
  final String? caption;

  bool get isImage => type == 'img';

  factory Block.fromJson(Map<String, dynamic> json) => Block(
    type: _asString(json['type']),
    text: _asStringOrNull(json['text']),
    src: _asStringOrNull(json['src']),
    local: _asStringOrNull(json['local']),
    caption: _asStringOrNull(json['caption']),
  );
}

class Article {
  const Article({
    required this.title,
    required this.url,
    this.author,
    this.blocks = const [],
  });

  final String title;
  final String url;
  final String? author;
  final List<Block> blocks;

  factory Article.fromJson(Map<String, dynamic> json) => Article(
    title: _asString(json['title']).trim(),
    url: _asString(json['url']),
    author: _asStringOrNull(json['author']),
    blocks: (json['blocks'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(Block.fromJson)
        .toList(growable: false),
  );
}

class ArticlePage {
  const ArticlePage({
    required this.date,
    required this.pageNo,
    required this.title,
    required this.kind,
    this.articles = const [],
  });

  final String date;
  final int pageNo;
  final String title;
  final PageKind kind;
  final List<Article> articles;

  factory ArticlePage.fromJson(Map<String, dynamic> json) => ArticlePage(
    date: _asString(json['date']),
    pageNo: _asInt(json['pageNo']),
    title: _asString(json['title']),
    kind: _kindFrom(_asString(json['kind'])),
    articles: (json['articles'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(Article.fromJson)
        .toList(growable: false),
  );
}
