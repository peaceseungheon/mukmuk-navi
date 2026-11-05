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

/// 검색 화면을 열고 "ㅁㅁ"로 검색한 뒤, 고른 결과를 [picked]에 담는다.
Future<void> _searchAndPick(
  WidgetTester tester,
  FakeNaviEngine engine,
  void Function(SearchPick?) onPicked,
  Future<void> Function() act,
) async {
  final tts = FakeTtsSpeaker();
  final services = AppServices(
    engine: engine,
    info: fakeInfo(),
    tts: tts,
    ttsAvailable: true,
    nav: NavigationController(engine: engine, tts: tts),
  );

  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async {
              onPicked(
                await Navigator.of(context).push<SearchPick>(
                  MaterialPageRoute(
                    builder: (_) => SearchScreen(services: services),
                  ),
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
  await tester.enterText(find.byType(TextField), 'ㅁㅁ');
  await tester.tap(find.byIcon(Icons.search));
  await tester.pumpAndSettle();
  await act();
  await tester.pumpAndSettle();
}

void main() {
  late FakeNaviEngine engine;

  setUp(() {
    engine = FakeNaviEngine()
      ..poiResults.addAll([_poi(1, '묵묵카페', 120), _poi(2, '묵묵약국', 1200)]);
  });

  testWidgets('검색 결과를 거리 표시와 함께 보여주고, 고르면 목적지 SearchPick을 돌려준다', (
    tester,
  ) async {
    SearchPick? picked;
    await _searchAndPick(tester, engine, (p) => picked = p, () async {
      // 기본 반경은 50km 칩이 선택되어 있다.
      final fiftyChip = tester.widget<ChoiceChip>(
        find.widgetWithText(ChoiceChip, '50km'),
      );
      expect(fiftyChip.selected, isTrue);

      expect(find.text('묵묵카페'), findsOneWidget);
      expect(find.text('120m'), findsOneWidget);
      expect(find.text('1.2km'), findsOneWidget);

      await tester.tap(find.text('묵묵카페'));
    });

    expect(picked?.poi.id, BigInt.from(1));
    expect(picked?.asWaypoint, isFalse);
  });

  testWidgets('결과의 경유지 아이콘을 누르면 경유지 SearchPick을 돌려준다', (tester) async {
    SearchPick? picked;
    await _searchAndPick(tester, engine, (p) => picked = p, () async {
      await tester.tap(
        find.widgetWithIcon(IconButton, Icons.add_location_alt).at(1),
      );
    });

    expect(picked?.poi.id, BigInt.from(2));
    expect(picked?.asWaypoint, isTrue);
  });
}
