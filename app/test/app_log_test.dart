import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rmrb_reader/core/app_log.dart';

void main() {
  test('UTF-8 logs rotate by bytes and remain within the total budget', () {
    final directory = Directory.systemTemp.createTempSync('chaowen-log-test-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final writer = RollingLog(directory, maxBytes: 256, backups: 2);
    for (var i = 0; i < 100; i++) {
      writer.write('INFO', 'event=$i ${'中' * 100}');
    }
    final files = directory
        .listSync()
        .whereType<File>()
        .where((f) => f.path.contains('app.log'))
        .toList();
    expect(files.length, lessThanOrEqualTo(3));
    expect(files.every((file) => file.lengthSync() <= 256), isTrue);
    expect(
      File('${directory.path}/app.log').readAsStringSync(),
      contains('event=99'),
    );
  });

  test(
    'crash capture keeps type and stack without serializing article content',
    () {
      final directory = Directory.systemTemp.createTempSync(
        'chaowen-crash-test-',
      );
      addTearDown(() => directory.deleteSync(recursive: true));
      AppLog.configure(RollingLog(directory));
      AppLog.capture(
        'test.crash',
        StateError('PRIVATE_ARTICLE_BODY'),
        StackTrace.current,
      );
      final text = File('${directory.path}/app.log').readAsStringSync();
      expect(text, contains('StateError'));
      expect(text, contains('app_log_test.dart'));
      expect(text, isNot(contains('PRIVATE_ARTICLE_BODY')));
      AppLog.configure(null);
    },
  );

  test('a log path failure cannot crash the reader', () {
    final directory = Directory.systemTemp.createTempSync('chaowen-log-error-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final file = File('${directory.path}/not-a-directory')
      ..writeAsStringSync('x');
    expect(
      () => RollingLog(Directory(file.path)).write('ERROR', 'failure'),
      returnsNormally,
    );
  });
}
