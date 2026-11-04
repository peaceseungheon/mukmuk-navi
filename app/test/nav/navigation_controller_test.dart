import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mukmuk_app/config.dart';
import 'package:mukmuk_app/ffibindings/api/types.dart';
import 'package:mukmuk_app/nav/navigation_controller.dart';
import 'package:mukmuk_app/nav/position_source.dart';

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
    nav.startRoute(fakeRoute(const [GeoPoint(lat: 1, lon: 1)]));
    nav.offRoute.value = true;

    final next = fakeRoute(const [
      GeoPoint(lat: 2, lon: 2),
      GeoPoint(lat: 3, lon: 3),
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
    nav.startRoute(fakeRoute(const [GeoPoint(lat: 1, lon: 1)]));

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
    nav.startRoute(fakeRoute(const [GeoPoint(lat: 1, lon: 1)]));
    engine.updateGate = Completer<void>();

    final first = nav.onFix(_fix());
    clock.advance(kPositionMinInterval * 2);
    await nav.onFix(_fix());
    expect(engine.positionCalls.length, 1);

    engine.updateGate!.complete();
    await first;
  });

  test('스냅 결과는 위치와 이탈 플래그에 반영된다', () async {
    nav.startRoute(fakeRoute(const [GeoPoint(lat: 1, lon: 1)]));
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
    nav.startRoute(fakeRoute(const [GeoPoint(lat: 1, lon: 1)]));
    engine.updateError = const EngineError.routingFailed('x');

    await nav.onFix(_fix());
    expect(nav.notice.value, '경로를 찾지 못했습니다.');
  });
}
