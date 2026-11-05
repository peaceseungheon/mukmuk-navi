import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mukmuk_app/ffibindings/api/types.dart';
import 'package:mukmuk_app/map/place_sheet.dart';
import 'package:mukmuk_app/map/tapped_place.dart';

void main() {
  TappedPlace named() => TappedPlace(
    name: '대전역',
    point: const GeoPoint(lat: 36.3513, lon: 127.3843),
    category: 'transit',
    addr: '대전 동구',
    nearbyDistanceM: 42,
  );

  Future<PlaceAction?> openAndTap(
    WidgetTester tester,
    TappedPlace place,
    String label,
  ) async {
    PlaceAction? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await showPlaceSheet(context, place);
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text(place.name), findsOneWidget);
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
    return result;
  }

  testWidgets('여기로 가기를 누르면 goHere를 돌려준다', (tester) async {
    final action = await openAndTap(tester, named(), '여기로 가기');
    expect(action, PlaceAction.goHere);
  });

  testWidgets('경유지로 추가를 누르면 addWaypoint를 돌려준다', (tester) async {
    final action = await openAndTap(tester, named(), '경유지로 추가');
    expect(action, PlaceAction.addWaypoint);
  });

  testWidgets('출발지로 설정을 누르면 setOrigin을 돌려준다', (tester) async {
    final action = await openAndTap(tester, named(), '출발지로 설정');
    expect(action, PlaceAction.setOrigin);
  });

  testWidgets('장소가 없는 지점은 좌표와 안내를 보여준다', (tester) async {
    const tap = TappedPlace(
      name: '선택한 위치',
      point: GeoPoint(lat: 36.35, lon: 127.38),
    );
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: PlaceSheet(place: tap)),
      ),
    );

    expect(find.text('주변 장소 없음'), findsOneWidget);
    expect(find.text('36.35000, 127.38000'), findsOneWidget);
  });
}
