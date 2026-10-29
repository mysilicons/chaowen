import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'core/engine_client.dart';
import 'state/providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await windowManager.ensureInitialized();
  const options = WindowOptions(
    size: Size(1280, 820),
    minimumSize: Size(1024, 700),
    center: true,
    title: '朝闻 · 人民日报',
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
