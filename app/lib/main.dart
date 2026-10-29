import 'dart:math' as math;
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'core/engine_client.dart';
import 'state/providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await windowManager.ensureInitialized();

  // 125% 缩放的屏幕上，1280 逻辑像素会超出物理宽度；按屏幕比例收敛。
  final view = PlatformDispatcher.instance.views.first;
  final logical = view.physicalSize / view.devicePixelRatio;
  final size = Size(
    math.min(1280, logical.width * 0.92),
    math.min(820, logical.height * 0.90),
  );

  final options = WindowOptions(
    size: size,
    minimumSize: const Size(1024, 680),
    center: true,
    title: '人民日报 阅报器',
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
