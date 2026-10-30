import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'core/engine_client.dart';
import 'core/app_log.dart';
import 'state/providers.dart';

void main() {
  AppLog.initialize();
  runZonedGuarded(
    _launch,
    (error, stack) => AppLog.capture('uncaught.zone', error, stack),
  );
}

Future<void> _launch() async {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterError.onError = (details) {
    AppLog.capture(
      'flutter.error library=${details.library}',
      details.exception,
      details.stack ?? StackTrace.current,
    );
    FlutterError.presentError(details);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    AppLog.capture('uncaught.platform', error, stack);
    return true;
  };

  await windowManager.ensureInitialized();
  const options = WindowOptions(
    size: Size(1280, 820),
    minimumSize: Size(1024, 700),
    center: true,
    title: '朝闻',
  );
  await windowManager.waitUntilReadyToShow(options, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  final engine = EngineClient();
  runApp(
    ProviderScope(
      overrides: [engineProvider.overrideWithValue(engine)],
      child: RmrbApp(engine: engine),
    ),
  );
}
