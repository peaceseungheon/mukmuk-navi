import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mukmuk_app/app_services.dart';
import 'package:mukmuk_app/ffibindings/api/types.dart';
import 'package:mukmuk_app/nav/navigation_controller.dart';
import 'package:mukmuk_app/search/search_screen.dart';

import '../support/fakes.dart';

PoiResult _poi(int id, String name, double distanceM) => PoiResult(
  id: BigInt.from(id),
  name: name,
  category: 'cafe',
  addr: '대전 유성구',
  point: const GeoPoint(lat: 36.35, lon: 127.38),
  distanceM: distanceM,
);

void main() {
  testWidgets('검색 결과를 거리 표시와 함께 보여주고, 고르면 PoiResult를 돌려준다', (
    tester,
  ) async {
    final engine = FakeNaviEngine()
      ..poiResults.addAll([_poi(1, '묵묵카페', 120), _poi(2, '묵묵약국', 1200)]);
    final tts = FakeTtsSpeaker();
    final services = AppServices(
      engine: engine,
      info: fakeInfo(),
      tts: tts,
      ttsAvailable: true,
      nav: NavigationController(engine: engine, tts: tts),
    );

    PoiResult? picked;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                picked = await Navigator.of(context).push<PoiResult>(
                  MaterialPageRoute(
                    builder: (_) => SearchScreen(services: services),
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // 기본 반경은 50km 칩이 선택되어 있다.
    final fiftyChip = tester.widget<ChoiceChip>(
      find.widgetWithText(ChoiceChip, '50km'),
    );
    expect(fiftyChip.selected, isTrue);

    await tester.enterText(find.byType(TextField), 'ㅁㅁ');
    await tester.tap(find.byIcon(Icons.search));
    await tester.pumpAndSettle();

    expect(find.text('묵묵카페'), findsOneWidget);
    expect(find.text('120m'), findsOneWidget);
    expect(find.text('1.2km'), findsOneWidget);

    await tester.tap(find.text('묵묵카페'));
    await tester.pumpAndSettle();

    expect(picked?.id, BigInt.from(1));
  });
}
