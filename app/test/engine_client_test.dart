import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:rmrb_reader/core/engine_client.dart';
import 'package:rmrb_reader/core/models.dart';

/// 用内存通道模拟引擎，测试不需要真的起 Python 进程。
class FakeTransport implements EngineTransport {
  final _controller = StreamController<String>.broadcast();
  final List<String> sent = [];
  bool silent = false;
  int protocolVersion = 1;

  @override
  Stream<String> get lines => _controller.stream;

  @override
  void write(String line) {
    sent.add(line);
    if (silent) return;
    final request = jsonDecode(line) as Map<String, dynamic>;
    final id = request['id'];

    switch (request['method']) {
      case 'hello':
        push({
          'id': id,
          'ok': true,
          'result': {'protocol': protocolVersion, 'engine': '0.1.0'},
        });
      case 'issue.parse':
        push({
          'id': id,
          'ok': true,
          'result': {
            'date': '2026-10-29',
            'pageCount': 2,
            'pages': [
              {'no': 1, 'title': '要闻', 'url': 'https://x/1', 'pdfUrl': 'https://x/1.pdf'},
            ],
          },
        });
      default:
        push({
          'id': id,
          'ok': false,
          'error': {'code': 'UNKNOWN_METHOD', 'message': '未知方法'},
        });
    }
  }

  void push(Map<String, dynamic> payload) => _controller.add(jsonEncode(payload));

  void pushRaw(String line) => _controller.add(line);

  void pushEvent(String name, Map<String, dynamic> data) =>
      push({'event': name, 'data': data});

  @override
  Future<void> kill() async {
    await _controller.close();
  }
}

void main() {
  late FakeTransport transport;
  late EngineClient client;

  setUp(() {
    transport = FakeTransport();
    client = EngineClient(transportFactory: () async => transport);
  });

  test('start 完成握手并记录版本', () async {
    await client.start();

    expect(client.status.value, EngineState.ready);
    expect(client.protocol, 1);
    expect(client.engineVersion, '0.1.0');
  });

  test('call 返回协议结果', () async {
    await client.start();

    final result = await client.call('issue.parse', {'date': '2026-10-29'});

    expect(result, isA<Map<String, dynamic>>());
    expect((result as Map<String, dynamic>)['pageCount'], 2);
  });

  test('错误响应转成 EngineException', () async {
    await client.start();

    await expectLater(
      client.call('no.such.method'),
      throwsA(isA<EngineException>().having((e) => e.code, 'code', 'UNKNOWN_METHOD')),
    );
  });

  test('事件走独立通道，不干扰请求', () async {
    await client.start();
    final received = <EngineEvent>[];
    final subscription = client.events.listen(received.add);

    transport.pushEvent('download.progress', {'jobId': 'j1', 'done': 3, 'total': 20});
    await Future<void>.delayed(Duration.zero);

    expect(received, hasLength(1));
    expect(received.first.name, 'download.progress');
    expect(received.first.data['done'], 3);
    await subscription.cancel();
  });

  test('非法协议行被记录但不崩溃', () async {
    await client.start();

    transport.pushRaw('这不是 JSON');
    await Future<void>.delayed(Duration.zero);

    expect(client.stderrTail.any((line) => line.contains('非法协议行')), isTrue);
    expect(client.status.value, EngineState.ready);
  });

  test('超时抛 TIMEOUT', () async {
    await client.start();
    transport.silent = true;

    await expectLater(
      client.call('issue.parse', {'date': '2026-10-29'}, const Duration(milliseconds: 60)),
      throwsA(isA<EngineException>().having((e) => e.code, 'code', 'TIMEOUT')),
    );
  });

  test('协议版本不一致拒绝启动', () async {
    transport.protocolVersion = 9;

    await expectLater(client.start(), throwsA(isA<EngineException>()));
    expect(client.status.value, EngineState.failed);
  });
}
