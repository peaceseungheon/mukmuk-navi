import 'package:mukmuk_app/config.dart';
import 'package:mukmuk_app/engine/navi_engine.dart';
import 'package:mukmuk_app/ffibindings/api/types.dart';

/// 지도에서 탭한 지점의 식별 결과. 주변 장소가 있으면 그 장소 정보를, 없으면 좌표만 담는다.
class TappedPlace {
  const TappedPlace({
    required this.name,
    required this.point,
    this.category = '',
    this.addr,
    this.nearbyDistanceM,
  });

  final String name;

  /// 목적지·출발지로 쓸 좌표. 주변 장소가 있으면 그 장소의 좌표다.
  final GeoPoint point;
  final String category;
  final String? addr;

  /// 탭 지점에서 주변 장소까지 거리(m). 장소가 없으면 null.
  final double? nearbyDistanceM;

  /// 경로 계획에 넘길 목적지. 장소가 없는 지점은 id 0으로 표시한다.
  PoiResult toPoi() => PoiResult(
    id: BigInt.zero,
    name: name,
    category: category,
    addr: addr,
    point: point,
    distanceM: nearbyDistanceM ?? 0,
  );
}

/// 탭 지점 반경 [kTapPlaceRadiusKm] 안의 가장 가까운 장소를 찾는다. 엔진 오류는 호출자에게 전달한다.
Future<TappedPlace> resolveTappedPlace(NaviEngine engine, GeoPoint tap) async {
  final found = await engine.nearbyPoi(
    center: tap,
    radiusKm: kTapPlaceRadiusKm,
    limit: 1,
  );
  if (found.isEmpty) {
    return TappedPlace(name: '선택한 위치', point: tap);
  }
  final poi = found.first;
  return TappedPlace(
    name: poi.name,
    point: poi.point,
    category: poi.category,
    addr: poi.addr,
    nearbyDistanceM: poi.distanceM,
  );
}
