import 'dart:math' as math;

import 'package:mukmuk_app/ffibindings/api/types.dart';

/// 경로의 한 지점(경유지 또는 목적지).
final class Stop {
  const Stop({required this.name, required this.point});

  final String name;
  final GeoPoint point;
}

const kMaxWaypoints = 3; // 경유지 최대 개수(목적지 제외)
const kStopMergeRadiusM = 20.0; // 이전 지점과 이 거리 이내면 겹친 지점으로 보고 제외
const kWaypointPassRadiusM = 60.0; // 구간 전환 판정 B(지나침)
const kStaleRerouteToleranceM = 30.0; // 오래된 Rerouted 거르기

const _earthRadiusM = 6371000.0;
const _junctionMergeM = 1.0; // 구간 이음점 중복 제거 거리

double _rad(double deg) => deg * math.pi / 180;

/// 두 점의 대원 거리(m). 지구 반지름 6371km 구면 근사.
double haversineM(GeoPoint a, GeoPoint b) {
  final sLat = math.sin((_rad(b.lat) - _rad(a.lat)) / 2);
  final sLon = math.sin((_rad(b.lon) - _rad(a.lon)) / 2);
  final h =
      sLat * sLat + math.cos(_rad(a.lat)) * math.cos(_rad(b.lat)) * sLon * sLon;
  return 2 * _earthRadiusM * math.asin(math.min(1, math.sqrt(h)));
}

/// 직전 지점(첫 항목은 [origin])과 [kStopMergeRadiusM] 이내인 항목을 뺀다. 순서는 유지한다.
List<Stop> dedupeStops(GeoPoint origin, List<Stop> stops) {
  final kept = <Stop>[];
  var prev = origin;
  for (final stop in stops) {
    if (haversineM(prev, stop.point) <= kStopMergeRadiusM) continue;
    kept.add(stop);
    prev = stop.point;
  }
  return kept;
}

/// 구간 경로를 순서대로 이어 하나의 경로로 만든다. 구간이 1개면 그대로 돌려준다.
/// k>0 구간의 첫 점이 직전 끝점과 1m 이내면 첫 점을 버린다(같은 그래프 노드).
Route combineLegs(List<Route> legs) {
  assert(legs.isNotEmpty, 'combineLegs는 구간이 1개 이상이어야 한다');
  if (legs.length == 1) return legs.first;

  final polyline = <GeoPoint>[];
  final steps = <RouteStep>[];
  var distanceM = 0.0;
  var durationS = 0.0;
  for (var k = 0; k < legs.length; k++) {
    final leg = legs[k];
    final points = leg.polyline;
    final drop =
        k > 0 &&
        polyline.isNotEmpty &&
        points.isNotEmpty &&
        haversineM(polyline.last, points.first) <= _junctionMergeM;
    polyline.addAll(drop ? points.skip(1) : points);
    steps.addAll(leg.steps);
    distanceM += leg.totalDistanceM;
    durationS += leg.totalDurationS;
  }
  return Route(
    polyline: polyline,
    steps: steps,
    totalDistanceM: distanceM,
    totalDurationS: durationS,
  );
}
