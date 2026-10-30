import 'dart:async';

import 'engine_client.dart';
import 'models.dart';
import 'zaobao_models.dart';

class ZaobaoClient {
  ZaobaoClient(this.engine);
  final EngineClient engine;

  Future<Map<String, dynamic>> call(
    String method, [
    Map<String, dynamic>? params,
  ]) async {
    final result = await engine.call(method, params);
    if (result is! Map<String, dynamic>) {
      throw const EngineException('BAD_RESPONSE', '早报引擎返回格式不正确');
    }
    return result;
  }

  Future<ZaobaoArticle?> article(String id) async {
    final result = await call('zaobao.article.get', {'articleId': id});
    final value = result['article'];
    return result['cached'] == true && value is Map<String, dynamic>
        ? ZaobaoArticle.fromJson(value)
        : null;
  }

  Future<void> run(
    String method,
    Map<String, dynamic> params, {
    required bool Function() isCurrent,
    required void Function(String) onJob,
  }) async {
    String? job;
    Completer<void>? wake;
    final subscription = engine.events.listen((event) {
      if (event.name == 'zaobao.task.changed' &&
          event.data['jobId'] == job &&
          wake != null &&
          !wake.isCompleted) {
        wake.complete();
      }
    });
    try {
      final started = await call(method, params);
      job = started['jobId'] as String;
      if (isCurrent()) onJob(job);
      final deadline = DateTime.now().add(const Duration(minutes: 5));
      while (isCurrent() && DateTime.now().isBefore(deadline)) {
        wake = Completer<void>();
        final task = await call('zaobao.task.get', {'jobId': job});
        if (task['state'] == 'succeeded') return;
        if (task['state'] == 'failed') {
          final error = task['error'] as Map<String, dynamic>? ?? {};
          throw EngineException(
            error['code'] as String? ?? 'HTTP_ERROR',
            error['message'] as String? ?? '早报任务失败',
          );
        }
        if (task['state'] == 'cancelled') {
          throw const EngineException('CANCELLED', '早报任务已取消');
        }
        // Events wake immediately; polling only repairs a lost event or old engine.
        await Future.any([
          wake.future,
          Future<void>.delayed(const Duration(seconds: 2)),
        ]);
      }
      await call('zaobao.task.cancel', {'jobId': job});
      if (isCurrent()) throw const EngineException('TIMEOUT', '早报任务等待超时，已取消');
    } finally {
      // Detach immediately; stream cleanup must not gate an already completed task.
      unawaited(subscription.cancel());
    }
  }
}
