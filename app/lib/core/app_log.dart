import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// One bounded record at a time; cross-process file locking also covers rotation.
class RollingLog {
  RollingLog(this.directory, {this.maxBytes = 1024 * 1024, this.backups = 2});
  final Directory directory;
  final int maxBytes;
  final int backups;

  void write(String level, String message) {
    RandomAccessFile? lock;
    var locked = false;
    try {
      directory.createSync(recursive: true);
      lock = File(p.join(directory.path, 'app.lock'))
          .openSync(mode: FileMode.append);
      lock.lockSync(FileLock.exclusive);
      locked = true;
      final file = File(p.join(directory.path, 'app.log'));
      final bytes = _record(
        '${DateTime.now().toUtc().toIso8601String()} $level $message',
      );
      if (file.existsSync() && file.lengthSync() + bytes.length > maxBytes) {
        _rotate(file);
      }
      file.writeAsBytesSync(bytes, mode: FileMode.append, flush: true);
    } on FileSystemException {
      // Diagnostics must never become a new source of application failures.
    } finally {
      try {
        if (locked) lock?.unlockSync();
        lock?.closeSync();
      } on FileSystemException {
        // A failing disk must not recurse through the global exception hook.
      }
    }
  }

  List<int> _record(String text) {
    final limit = maxBytes < 8192 ? maxBytes : 8192;
    var bytes = utf8.encode(text);
    if (bytes.length >= limit) {
      final short = utf8.decode(
        bytes.sublist(0, limit - 8),
        allowMalformed: true,
      );
      bytes = utf8.encode('$short...');
    }
    return [...bytes, 10];
  }

  void _rotate(File current) {
    for (var i = backups; i >= 1; i--) {
      final target = File('${current.path}.$i');
      if (target.existsSync()) target.deleteSync();
      final source = i == 1 ? current : File('${current.path}.${i - 1}');
      if (source.existsSync()) source.renameSync(target.path);
    }
    if (backups == 0 && current.existsSync()) current.deleteSync();
  }
}

abstract final class AppLog {
  static RollingLog? _writer;

  static String get directory =>
      Platform.environment['CHAOWEN_LOG_DIR'] ??
      p.join(
        Platform.environment['LOCALAPPDATA'] ?? Directory.systemTemp.path,
        'rmrb-reader',
        'logs',
      );

  static void initialize() {
    configure(RollingLog(Directory(directory)));
    info('app.start pid=$pid');
  }

  static void configure(RollingLog? writer) => _writer = writer;
  static void info(String event) => _writer?.write('INFO', event);
  static void warning(String event) => _writer?.write('WARN', event);

  static void capture(String event, Object error, StackTrace stack) {
    // Types and code locations are diagnostic; article/credential payloads are not.
    _writer?.write('ERROR', '$event type=${error.runtimeType}\n$stack');
  }
}
