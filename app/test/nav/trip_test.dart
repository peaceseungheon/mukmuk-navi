import 'package:flutter_test/flutter_test.dart';
import 'package:mukmuk_app/ffibindings/api/types.dart';
import 'package:mukmuk_app/nav/trip.dart';

import '../support/fakes.dart';

/// 위도 1m ≈ 1/111195 도. 테스트 좌표를 미터 단위로 쓰기 위한 보조 값.
const _degPerM = 1 / 111195;

GeoPoint _northOf(GeoPoint p, double meters) =>
    GeoPoint(lat: p.lat + meters * _degPerM, lon: p.lon);

Route _leg(
  List<GeoPoint> points, {
  double distanceM = 0,
  double durationS = 0,
  List<RouteStep> steps = const [],
}) => Route(
  polyline: points,
  steps: steps,
  totalDistanceM: distanceM,
  totalDurationS: durationS,
);

void main() {
  const origin = GeoPoint(lat: 36.35, lon: 127.38);

  group('haversineM', () {
    test('위도 1도는 약 111.195km다', () {
      const a = GeoPoint(lat: 36, lon: 127);
      const b = GeoPoint(lat: 37, lon: 127);
      expect(haversineM(a, b), closeTo(111195, 1));
    });

    test('같은 점의 거리는 0이다', () {
      expect(haversineM(origin, origin), 0);
    });
  });

  group('dedupeStops', () {
    test('20m 이내 지점은 빼고 나머지는 입력 순서대로 남긴다', () {
      final near = Stop(name: '가까움', point: _northOf(origin, 10));
      final far1 = Stop(name: '먼1', point: _northOf(origin, 100));
      final near2 = Stop(name: '가까움2', point: _northOf(origin, 105));
      final far2 = Stop(name: '먼2', point: _northOf(origin, 300));

      final kept = dedupeStops(origin, [near, far1, near2, far2]);

      expect(kept.map((s) => s.name).toList(), ['먼1', '먼2']);
    });

    test('직전 지점은 마지막으로 남긴 지점이다', () {
      // far1에서 15m 떨어진 지점은 origin에서는 35m라 남지만, far1 기준으로는 제외된다.
      final far1 = Stop(name: '먼1', point: _northOf(origin, 30));
      final chained = Stop(name: '연쇄', point: _northOf(origin, 40));
      final kept = dedupeStops(origin, [far1, chained]);
      expect(kept.map((s) => s.name).toList(), ['먼1']);
    });

    test('모두 겹치면 빈 목록을 돌려준다', () {
      final kept = dedupeStops(origin, [
        Stop(name: 'a', point: _northOf(origin, 5)),
      ]);
      expect(kept, isEmpty);
    });
  });

  group('combineLegs', () {
    test('이음점이 1m 이내면 다음 구간 첫 점을 버린다', () {
      final a = GeoPoint(lat: 36.35, lon: 127.38);
      final b = GeoPoint(lat: 36.351, lon: 127.38);
      final c = GeoPoint(lat: 36.352, lon: 127.38);
      final bJitter = _northOf(b, 0.5);

      final combined = combineLegs([
        _leg([a, b]),
        _leg([bJitter, c]),
      ]);

      expect(combined.polyline.length, 3);
      expect(combined.polyline.first, a);
      expect(combined.polyline.last, c);
    });

    test('이음점이 1m를 넘으면 두 점을 모두 남긴다', () {
      final b = GeoPoint(lat: 36.351, lon: 127.38);
      final far = _northOf(b, 5);
      final combined = combineLegs([
        _leg([origin, b]),
        _leg([far, _northOf(far, 100)]),
      ]);
      expect(combined.polyline.length, 4);
    });

    test('거리와 시간은 구간 합이고 steps는 순서대로 이어 붙인다', () {
      final step1 = fakeStep(maneuver: Maneuver.left, roadName: '가');
      final step2 = fakeStep(maneuver: Maneuver.right, roadName: '나');
      final combined = combineLegs([
        _leg(const [origin], distanceM: 1200, durationS: 180, steps: [step1]),
        _leg(const [origin], distanceM: 800.5, durationS: 95.5, steps: [step2]),
      ]);

      expect(combined.totalDistanceM, closeTo(2000.5, 1e-9));
      expect(combined.totalDurationS, closeTo(275.5, 1e-9));
      expect(combined.steps.map((s) => s.roadName).toList(), ['가', '나']);
    });

    test('구간이 1개면 그 구간을 그대로 돌려준다', () {
      final only = fakeRoute(const [origin, GeoPoint(lat: 36.36, lon: 127.38)]);
      expect(identical(combineLegs([only]), only), isTrue);
    });
  });
}
