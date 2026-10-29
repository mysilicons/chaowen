import 'package:flutter_test/flutter_test.dart';
import 'package:rmrb_reader/app.dart';

void main() {
  testWidgets('骨架页渲染报头与说明', (tester) async {
    await tester.pumpWidget(const RmrbApp());

    expect(find.text('人民日报'), findsOneWidget);
    expect(find.text('阅报器 · 骨架已就绪'), findsOneWidget);
    expect(find.text('开始阅读'), findsOneWidget);
  });
}
