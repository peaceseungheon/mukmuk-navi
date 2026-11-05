import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mukmuk_app/config.dart';
import 'package:mukmuk_app/ffibindings/api/types.dart';
import 'package:mukmuk_app/nav/navigation_controller.dart';
import 'package:mukmuk_app/nav/position_source.dart';
import 'package:mukmuk_app/nav/trip.dart';

import '../support/fakes.dart';

/// 테스트용 시계. 위치 갱신 쓰로틀(10Hz)을 결정적으로 검증한다.
class _Clock {
  DateTime now = DateTime(2026, 11, 4, 9);
  DateTime call() => now;
  void advance(Duration d) => now = now.add(d);
}

RawFix _fix({int tMs = 0}) => RawFix(
  point: const GeoPoint(lat: 36.35, lon: 127.38),
  speedMps: 10,
  headingDeg: 90,
  tMs: tMs,
);

Future<void> _settle() => Future<void>.delayed(Duration.zero);

/// 구간 1개짜리 여정으로 시작한다(경유지 없는 기존 동작과 같다).
void startSingleLeg(NavigationController nav, Route route) {
  nav.startTrip([Stop(name: '목적지', point: route.polyline.last)], [route]);
}

void main() {
  late FakeNaviEngine engine;
  late FakeTtsSpeaker tts;
  late _Clock clock;
  late NavigationController nav;

  setUp(() {
    engine = FakeNaviEngine();
    tts = FakeTtsSpeaker();
    clock = _Clock();
    nav = NavigationController(engine: engine, tts: tts, now: clock.call);
  });

  tearDown(() async {
    await nav.dispose();
    await engine.events.close();
  });

  test('이벤트 구독은 여러 번 불러도 엔진에 한 번만 걸린다', () async {
    await nav.ensureSubscribed();
    await nav.ensureSubscribed();
    expect(engine.subscribeCount, 1);
  });

  test('Rerouted 이벤트는 경로를 즉시 교체하고 이탈 표시를 끈다', () async {
    await nav.ensureSubscribed();
    startSingleLeg(nav, fakeRoute(const [GeoPoint(lat: 1, lon: 1)]));
    nav.offRoute.value = true;

    // 재탐색은 같은 목적지(구간 끝)로 끝난다.
    final next = fakeRoute(const [
      GeoPoint(lat: 2, lon: 2),
      GeoPoint(lat: 1, lon: 1),
    ]);
    engine.events.add(NavigationEvent.rerouted(next));
    await _settle();

    expect(nav.route.value, same(next));
    expect(nav.offRoute.value, isFalse);
  });

  test('Instruction 이벤트는 안내 상태를 갱신하고 음성으로 발화한다', () async {
    await nav.ensureSubscribed();
    final step = fakeStep(maneuver: Maneuver.left, roadName: '대덕대로');
    engine.events.add(NavigationEvent.instruction(step));
    await _settle();

    expect(nav.instruction.value, same(step));
    expect(tts.spoken, ['300미터 앞에서 대덕대로, 좌회전.']);
  });

  test('Arrived 이벤트는 도착 상태를 켠다', () async {
    await nav.ensureSubscribed();
    engine.events.add(const NavigationEvent.arrived());
    await _settle();
    expect(nav.arrived.value, isTrue);
  });

  test('10Hz 상한: 100ms 안의 연속 위치는 엔진에 전달되지 않는다', () async {
    startSingleLeg(nav, fakeRoute(const [GeoPoint(lat: 1, lon: 1)]));

    await nav.onFix(_fix());
    await nav.onFix(_fix());
    clock.advance(const Duration(milliseconds: 50));
    await nav.onFix(_fix());
    expect(engine.positionCalls.length, 1);

    clock.advance(kPositionMinInterval);
    await nav.onFix(_fix());
    expect(engine.positionCalls.length, 2);
  });

  test('경로가 없으면 위치를 엔진에 보내지 않는다', () async {
    await nav.onFix(_fix());
    expect(engine.positionCalls, isEmpty);
  });

  test('이전 update_position이 끝나지 않았으면 새 위치는 버린다', () async {
    startSingleLeg(nav, fakeRoute(const [GeoPoint(lat: 1, lon: 1)]));
    engine.updateGate = Completer<void>();

    final first = nav.onFix(_fix());
    clock.advance(kPositionMinInterval * 2);
    await nav.onFix(_fix());
    expect(engine.positionCalls.length, 1);

    engine.updateGate!.complete();
    await first;
  });

  test('스냅 결과는 위치와 이탈 플래그에 반영된다', () async {
    startSingleLeg(nav, fakeRoute(const [GeoPoint(lat: 1, lon: 1)]));
    engine.onUpdate = (pos) => SnappedPosition(
      point: const GeoPoint(lat: 36.351, lon: 127.381),
      roadId: BigInt.one,
      distanceToRouteM: 80,
      offRoute: true,
    );

    await nav.onFix(_fix());
    expect(nav.position.value?.lat, 36.351);
    expect(nav.offRoute.value, isTrue);
  });

  test('update_position 실패는 사용자 문구로 notice에 올린다', () async {
    startSingleLeg(nav, fakeRoute(const [GeoPoint(lat: 1, lon: 1)]));
    engine.updateError = const EngineError.routingFailed('x');

    await nav.onFix(_fix());
    expect(nav.notice.value, '경로를 찾지 못했습니다.');
  });

  group('구간 전환 (경유지 도착)', () {
    // 출발 → 경유지(북쪽 약 1.1km) → 목적지(경유지에서 북쪽 약 1.1km).
    const origin = GeoPoint(lat: 36.35, lon: 127.38);
    const waypoint = GeoPoint(lat: 36.36, lon: 127.38);
    const dest = GeoPoint(lat: 36.37, lon: 127.38);
    const midway = GeoPoint(lat: 36.355, lon: 127.38);
    // 경유지 20m 앞: 도착 신호를 받을 만큼 가깝고 아직 이탈은 아닌 위치.
    const beforeEnd = GeoPoint(lat: 36.35982, lon: 127.38);

    /// 경유지 끝에서 [meters]만큼 북쪽으로 떨어진 점.
    GeoPoint north(GeoPoint p, double meters) =>
        GeoPoint(lat: p.lat + meters / 111195, lon: p.lon);

    Future<void> startTwoLegs() async {
      await nav.ensureSubscribed();
      nav.startTrip(
        const [
          Stop(name: '경유1', point: waypoint),
          Stop(name: '목적지', point: dest),
        ],
        [
          fakeRoute(const [origin, waypoint]),
          fakeRoute(const [waypoint, dest]),
        ],
      );
    }

    SnappedPosition snapped(GeoPoint p, {required bool off}) => SnappedPosition(
      point: p,
      roadId: BigInt.zero,
      distanceToRouteM: off ? 40 : 0,
      offRoute: off,
    );

    test('중간 Arrived는 다음 구간을 계획하고 도착 상태를 켜지 않는다', () async {
      await startTwoLegs();
      engine.events.add(const NavigationEvent.arrived());
      await _settle();

      expect(nav.activeLeg.value, 1);
      expect(nav.arrived.value, isFalse);
      expect(engine.planCalls.single.start, waypoint);
      expect(engine.planCalls.single.end, dest);
      expect(tts.spoken, ['경유지 1에 도착했습니다. 목적지로 안내합니다.']);
    });

    test('마지막 구간의 Arrived는 도착 상태를 켠다', () async {
      await startTwoLegs();
      engine.events.add(const NavigationEvent.arrived());
      await _settle();
      engine.events.add(const NavigationEvent.arrived());
      await _settle();

      expect(nav.arrived.value, isTrue);
      expect(engine.planCalls.length, 1);
    });

    test('구간 끝에서 먼 곳의 Arrived는 옛 구간의 늦은 신호로 보고 무시한다', () async {
      await startTwoLegs();
      engine.onUpdate = (p) => snapped(midway, off: false);
      await nav.onFix(_fix());

      engine.events.add(const NavigationEvent.arrived());
      await _settle();

      expect(nav.activeLeg.value, 0);
      expect(engine.planCalls, isEmpty);
    });

    test('이탈 상태에서 경유지 60m 이내면 지나친 것으로 보고 다음 구간으로 넘어간다', () async {
      await startTwoLegs();
      engine.onUpdate = (p) => snapped(north(waypoint, 40), off: true);
      await nav.onFix(_fix());

      expect(nav.activeLeg.value, 1);
      expect(engine.planCalls.single.end, dest);
      expect(nav.offRoute.value, isFalse);
    });

    test('이탈 상태라도 경유지에서 60m를 넘게 떨어져 있으면 넘어가지 않는다', () async {
      await startTwoLegs();
      engine.onUpdate = (p) => snapped(north(waypoint, 200), off: true);
      await nav.onFix(_fix());

      expect(nav.activeLeg.value, 0);
      expect(engine.planCalls, isEmpty);
    });

    test('새 구간의 첫 출발 안내는 발화하지 않고 카드에만 반영한다', () async {
      await startTwoLegs();
      engine.events.add(const NavigationEvent.arrived());
      await _settle();

      engine.events.add(
        NavigationEvent.instruction(fakeStep(maneuver: Maneuver.depart)),
      );
      await _settle();
      expect(nav.instruction.value?.maneuver, Maneuver.depart);
      expect(tts.spoken.length, 1);

      engine.events.add(
        NavigationEvent.instruction(fakeStep(maneuver: Maneuver.left)),
      );
      await _settle();
      expect(tts.spoken.last, '300미터 앞에서 좌회전.');
    });

    test('다음 구간 계획이 실패하면 경유지 기준으로 한 번 더 계획한다', () async {
      await startTwoLegs();
      engine.onUpdate = (p) => snapped(beforeEnd, off: false);
      await nav.onFix(_fix());
      engine.planError = (start, end) => start.lat == beforeEnd.lat
          ? const EngineError.routingFailed('x')
          : null;

      engine.events.add(const NavigationEvent.arrived());
      await _settle();

      expect(engine.planCalls.map((c) => c.start.lat).toList(), [
        beforeEnd.lat,
        waypoint.lat,
      ]);
      expect(nav.activeLeg.value, 1);
      expect(nav.notice.value, isNull);
    });

    test('재시도도 실패하면 안내 문구를 남기고 이후 도착 신호에 다시 계획하지 않는다', () async {
      await startTwoLegs();
      engine.planError = (start, end) => const EngineError.routingFailed('x');

      engine.events.add(const NavigationEvent.arrived());
      await _settle();
      expect(nav.notice.value, '다음 구간 경로를 찾지 못했습니다. 경로를 찾지 못했습니다.');
      expect(nav.activeLeg.value, 0);
      expect(nav.arrived.value, isFalse);
      expect(engine.planCalls.length, 2);

      engine.events.add(const NavigationEvent.arrived());
      await _settle();
      expect(engine.planCalls.length, 2);
    });
  });

  group('재탐색과 경유 순서', () {
    const origin = GeoPoint(lat: 36.35, lon: 127.38);
    const w1 = GeoPoint(lat: 36.355, lon: 127.38);
    const w2 = GeoPoint(lat: 36.36, lon: 127.38);
    const dest = GeoPoint(lat: 36.37, lon: 127.38);

    Future<void> startThreeLegs() async {
      await nav.ensureSubscribed();
      nav.startTrip(
        const [
          Stop(name: '경유1', point: w1),
          Stop(name: '경유2', point: w2),
          Stop(name: '목적지', point: dest),
        ],
        [
          fakeRoute(const [origin, w1]),
          fakeRoute(const [w1, w2]),
          fakeRoute(const [w2, dest]),
        ],
      );
    }

    test('남은 경유지 좌표는 도착할 때마다 하나씩 줄고 목적지는 포함하지 않는다', () async {
      await startThreeLegs();
      expect(nav.waypoints.value, [w1, w2]);

      engine.events.add(const NavigationEvent.arrived());
      await _settle();
      expect(nav.waypoints.value, [w2]);

      engine.events.add(const NavigationEvent.arrived());
      await _settle();
      expect(nav.waypoints.value, isEmpty);
      expect(nav.arrived.value, isFalse);
    });

    test('끝점이 활성 구간 끝에서 30m를 넘게 어긋난 재탐색은 버린다', () async {
      await nav.ensureSubscribed();
      nav.startTrip(
        const [Stop(name: '경유1', point: w1), Stop(name: '목적지', point: dest)],
        [
          fakeRoute(const [origin, w1]),
          fakeRoute(const [w1, dest]),
        ],
      );
      engine.events.add(const NavigationEvent.arrived());
      await _settle();
      final before = nav.route.value;
      nav.offRoute.value = true;

      // 옛 구간(출발 → 경유1) 기준 재탐색: 끝점이 활성 구간(→ 목적지)의 끝과 멀다.
      engine.events.add(
        NavigationEvent.rerouted(fakeRoute(const [origin, w1])),
      );
      await _settle();

      expect(nav.route.value, same(before));
      expect(nav.offRoute.value, isTrue);
    });

    test('재탐색은 활성 구간만 바꾸고 남은 구간과 이어 보여준다', () async {
      await startThreeLegs();
      engine.events.add(const NavigationEvent.arrived());
      await _settle();
      expect(nav.activeLeg.value, 1);

      const midway = GeoPoint(lat: 36.357, lon: 127.38);
      final rerouted = Route(
        polyline: const [midway, w2],
        steps: const [],
        totalDistanceM: 500,
        totalDurationS: 60,
      );
      engine.events.add(NavigationEvent.rerouted(rerouted));
      await _settle();

      // 활성 구간(재탐색 500m) + 남은 구간(fakeRoute 1200m).
      expect(nav.route.value?.totalDistanceM, closeTo(1700, 1e-9));
      expect(nav.route.value?.polyline.last, dest);
      expect(nav.offRoute.value, isFalse);
    });
  });
}
