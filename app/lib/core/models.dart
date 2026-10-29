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
