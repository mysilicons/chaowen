import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'models.dart';

/// 与引擎的传输通道。抽象出来是为了让测试不需要真的起进程。
abstract class EngineTransport {
  Stream<String> get lines;
  void write(String line);
  Future<void> kill();
}

class ProcessTransport implements EngineTransport {
  ProcessTransport(this._process);

  final Process _process;

  @override
  Stream<String> get lines =>
      _process.stdout.transform(utf8.decoder).transform(const LineSplitter());

  @override
  void write(String line) {
    // 不显式设置的话，Windows 上 IOSink 会用系统代码页（GBK）编码，
    // 而引擎按 UTF-8 解码，中文路径就成乱码了。
    _process.stdin.encoding = utf8;
    _process.stdin.writeln(line);
  }

  @override
  Future<void> kill() async {
    _process.kill();
  }
}

/// 引擎进程定位：开发态从仓库根找 `engine/`，发布态从可执行文件旁找。
String resolveEngineDir() {
  final override = Platform.environment['RMRB_ENGINE_DIR'];
  if (override != null && override.isNotEmpty) return override;

  var dir = Directory.current;
  for (var depth = 0; depth < 10; depth++) {
    final candidate = p.join(dir.path, 'engine');
    if (File(p.join(candidate, 'pyproject.toml')).existsSync()) return candidate;
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  throw StateError('找不到 engine 目录：请在仓库内运行，或设置 RMRB_ENGINE_DIR');
}

class EngineClient {
  EngineClient({Future<EngineTransport> Function()? transportFactory})
    : _transportFactory = transportFactory ?? _spawn;

  final Future<EngineTransport> Function() _transportFactory;

  final _events = StreamController<EngineEvent>.broadcast();
  final _pending = <int, Completer<Object?>>{};
  final _stderrTail = <String>[];

  EngineTransport? _transport;
  StreamSubscription<String>? _subscription;
  int _nextId = 0;
  bool _disposed = false;

  final status = ValueNotifier<EngineState>(EngineState.idle);
  String? engineVersion;
  int protocol = 0;
  String? lastError;

  Stream<EngineEvent> get events => _events.stream;

  List<String> get stderrTail => List.unmodifiable(_stderrTail);

  /// 发布态：引擎随应用分发在 `<exe 目录>/engine/rmrb_engine.exe`。
  static String? bundledEnginePath() {
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    final candidate = p.join(exeDir, 'engine', 'rmrb_engine.exe');
    return File(candidate).existsSync() ? candidate : null;
  }

  static Future<EngineTransport> _spawn() async {
    final bundled = bundledEnginePath();
    if (bundled != null) {
      final process = await Process.start(
        bundled,
        ['--serve'],
        workingDirectory: File(bundled).parent.path,
      );
      return ProcessTransport(process);
    }

    // 开发态：仓库里用 uv 跑源码
    final engineDir = resolveEngineDir();
    final process = await Process.start(
      'uv',
      ['run', 'python', '-m', 'rmrb_engine', '--serve'],
      workingDirectory: engineDir,
      runInShell: true,
    );
    return ProcessTransport(process);
  }

  Future<void> start({Duration timeout = const Duration(seconds: 20)}) async {
    if (status.value == EngineState.ready || status.value == EngineState.starting) return;
    status.value = EngineState.starting;
    lastError = null;

    try {
      final transport = await _transportFactory();
      _transport = transport;
      _subscription = transport.lines.listen(
        _onLine,
        onError: (Object error) => _fail(error.toString()),
        onDone: () => _fail('引擎进程已退出'),
      );
      final hello = await call(
        'hello',
        {'protocol': 1, 'client': 'rmrb-reader/0.1.0'},
        timeout,
      );
      final helloMap = hello is Map<String, dynamic> ? hello : const <String, dynamic>{};
      protocol = (helloMap['protocol'] as num?)?.toInt() ?? 0;
      engineVersion = helloMap['engine'] as String?;
      if (protocol != 1) {
        throw EngineException('PROTOCOL_MISMATCH', '引擎协议版本不匹配：$protocol');
      }
      status.value = EngineState.ready;
    } catch (error) {
      lastError = error.toString();
      status.value = EngineState.failed;
      await _teardown();
      rethrow;
    }
  }

  Future<Object?> call(
    String method, [
    Map<String, dynamic>? params,
    Duration timeout = const Duration(seconds: 30),
  ]) {
    final transport = _transport;
    if (transport == null) {
      throw const EngineException('ENGINE_NOT_READY', '引擎尚未启动');
    }
    final id = _nextId++;
    final completer = Completer<Object?>();
    _pending[id] = completer;

    final payload = <String, dynamic>{'id': id, 'method': method};
    if (params != null) payload['params'] = params;
    transport.write(jsonEncode(payload));

    return completer.future.timeout(
      timeout,
      onTimeout: () {
        _pending.remove(id);
        throw EngineException('TIMEOUT', '引擎响应超时：$method');
      },
    );
  }

  void _onLine(String line) {
    if (line.trim().isEmpty) return;
    late final Map<String, dynamic> message;
    try {
      final decoded = jsonDecode(line);
      if (decoded is! Map<String, dynamic>) return;
      message = decoded;
    } catch (_) {
      // 协议流被污染是严重问题，留证据但不炸客户端
      _stderrTail.add('非法协议行: $line');
      return;
    }

    if (message['event'] is String) {
      final data = message['data'];
      _events.add(
        EngineEvent(
          message['event'] as String,
          data is Map<String, dynamic> ? data : const {},
        ),
      );
      return;
    }

    final id = message['id'];
    if (id is! int) return;
    final completer = _pending.remove(id);
    if (completer == null) return;

    if (message['ok'] == true) {
      completer.complete(message['result']);
    } else {
      final error = message['error'];
      final map = error is Map<String, dynamic> ? error : const <String, dynamic>{};
      completer.completeError(
        EngineException(
          map['code'] as String? ?? 'UNKNOWN',
          map['message'] as String? ?? '未知错误',
          detail: map['detail'] as String?,
        ),
      );
    }
  }

  void _fail(String reason) {
    if (_disposed) return;
    status.value = EngineState.crashed;
    lastError = reason;
    for (final completer in _pending.values) {
      if (!completer.isCompleted) {
        completer.completeError(EngineException('ENGINE_EXITED', reason));
      }
    }
    _pending.clear();
  }

  Future<void> _teardown() async {
    await _subscription?.cancel();
    _subscription = null;
    await _transport?.kill();
    _transport = null;
  }

  Future<void> dispose() async {
    _disposed = true;
    await _teardown();
    await _events.close();
  }
}
