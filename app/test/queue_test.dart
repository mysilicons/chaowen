import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rmrb_reader/core/engine_client.dart';
import 'package:rmrb_reader/core/models.dart';
import 'package:rmrb_reader/state/providers.dart';

/// 只暴露事件流的假引擎，用来驱动队列状态。
class EventOnlyEngine extends EngineClient {
  final controller = StreamController<EngineEvent>.broadcast();

  @override
  Stream<EngineEvent> get events => controller.stream;

  @override
  Future<Object?> call(
    String method, [
    Map<String, dynamic>? params,
    Duration timeout = const Duration(seconds: 30),
  ]) async => {};
}

void main() {
  test('批量任务标题跟随当前下载的那一天', () async {
    final engine = EventOnlyEngine();
    final container = ProviderContainer(
      overrides: [engineProvider.overrideWithValue(engine)],
    );
    addTearDown(container.dispose);

    // 建立队列订阅
    container.read(queueProvider);

    engine.controller.add(
      EngineEvent('batch.progress', {
        'jobId': 'batch-1',
        'date': '2026-10-23',
        'index': 1,
        'total': 7,
      }),
    );
    await Future<void>.delayed(Duration.zero);

    var jobs = container.read(queueProvider);
    expect(jobs, hasLength(1));
    expect(jobs.first.date, '2026-10-23');
    expect(jobs.first.done, 1);
    expect(jobs.first.total, 7);

    engine.controller.add(
      EngineEvent('batch.progress', {
        'jobId': 'batch-1',
        'date': '2026-10-24',
        'index': 2,
        'total': 7,
      }),
    );
    await Future<void>.delayed(Duration.zero);

    jobs = container.read(queueProvider);
    expect(jobs, hasLength(1));
    expect(jobs.first.date, '2026-10-24', reason: '标题必须跟着推进的日期变化');
    expect(jobs.first.done, 2);
  });

  test('单日下载按版推进进度', () async {
    final engine = EventOnlyEngine();
    final container = ProviderContainer(
      overrides: [engineProvider.overrideWithValue(engine)],
    );
    addTearDown(container.dispose);
    container.read(queueProvider);

    engine.controller.add(
      EngineEvent('download.progress', {
        'jobId': '20261029-1',
        'date': '2026-10-29',
        'pageNo': 5,
        'done': 5,
        'total': 20,
      }),
    );
    await Future<void>.delayed(Duration.zero);

    final job = container.read(queueProvider).first;
    expect(job.date, '2026-10-29');
    expect(job.currentPage, 5);
    expect(job.progress, closeTo(0.25, 1e-9));
  });
}
