import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'zaobao_view_test.dart' show NewsEngine, mount;

// Opt-in local visual QA; artifacts go to the ignored workspace cache.
const enabled = bool.fromEnvironment('ZAOBAO_VISUAL_QA');

void main() {
  setUpAll(() async {
    if (!enabled) return;
    final font = FontLoader('ChaoWenSerif')
      ..addFont(rootBundle.load('assets/fonts/SourceHanSerifSC-Regular.ttf'))
      ..addFont(rootBundle.load('assets/fonts/SourceHanSerifSC-Bold.ttf'));
    await font.load();
    final sansPath = File(
      '${Platform.environment['WINDIR'] ?? 'C:/Windows'}/Fonts/msyh.ttc',
    );
    if (await sansPath.exists()) {
      final sans = FontLoader('Roboto')
        ..addFont(
          Future.value(ByteData.sublistView(await sansPath.readAsBytes())),
        );
      await sans.load();
    }
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
  });

  for (final brightness in Brightness.values) {
    testWidgets('newspaper layout visual QA ${brightness.name}', (
      tester,
    ) async {
      await mount(
        tester,
        NewsEngine(extraItems: 15),
        size: const Size(810, 700),
        brightness: brightness,
      );
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(Scaffold),
        matchesGoldenFile('../../cache/zaobao-ui-${brightness.name}.png'),
      );
    }, skip: !enabled);
  }
}
