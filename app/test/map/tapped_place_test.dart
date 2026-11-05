import 'package:flutter_test/flutter_test.dart';
import 'package:mukmuk_app/ffibindings/api/types.dart';
import 'package:mukmuk_app/map/tapped_place.dart';

import '../support/fakes.dart';

void main() {
  const tap = GeoPoint(lat: 36.35, lon: 127.38);

  test('주변 장소가 있으면 가장 가까운 장소 정보를 쓴다', () async {
    final engine = FakeNaviEngine()
      ..nearbyResults.add(
        PoiResult(
          id: BigInt.from(7),
          name: '대전역',
          category: 'transit',
          addr: '대전 동구',
          point: const GeoPoint(lat: 36.3513, lon: 127.3843),
          distanceM: 42,
        ),
      );

    final place = await resolveTappedPlace(engine, tap);

    expect(engine.nearbyCalls, [tap]);
    expect(place.name, '대전역');
    expect(place.category, 'transit');
    expect(place.addr, '대전 동구');
    expect(place.nearbyDistanceM, 42);
    // 목적지 좌표는 탭 지점이 아니라 장소 좌표다.
    expect(place.point.lat, 36.3513);
  });

  test('주변 장소가 없으면 탭한 좌표를 그대로 쓴다', () async {
    final engine = FakeNaviEngine();

    final place = await resolveTappedPlace(engine, tap);

    expect(place.name, '선택한 위치');
    expect(place.point, tap);
    expect(place.nearbyDistanceM, isNull);
  });

  test('toPoi는 장소가 없으면 id 0 목적지를 만든다', () async {
    final engine = FakeNaviEngine();
    final place = await resolveTappedPlace(engine, tap);

    final poi = place.toPoi();

    expect(poi.id, BigInt.zero);
    expect(poi.name, '선택한 위치');
    expect(poi.point, tap);
    expect(poi.distanceM, 0);
  });
}
