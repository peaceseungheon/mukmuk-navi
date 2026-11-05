import 'package:flutter_test/flutter_test.dart';
import 'package:mukmuk_app/app_services.dart';
import 'package:mukmuk_app/ffibindings/api/types.dart';
import 'package:mukmuk_app/nav/navigation_controller.dart';
import 'package:mukmuk_app/nav/trip.dart';

import 'support/fakes.dart';

AppServices _services() {
  final engine = FakeNaviEngine();
  final tts = FakeTtsSpeaker();
  return AppServices(
    engine: engine,
    info: fakeInfo(),
    tts: tts,
    ttsAvailable: true,
    nav: NavigationController(engine: engine, tts: tts),
  );
}

Stop _stop(int i) => Stop(
  name: '경유$i',
  point: GeoPoint(lat: 36.35 + i * 0.01, lon: 127.38),
);

void main() {
  test('경유지는 끝에 추가되고 최대 개수에 도달하면 추가를 거절한다', () {
    final services = _services();
    addTearDown(services.dispose);

    for (var i = 1; i <= kMaxWaypoints; i++) {
      expect(services.addWaypoint(_stop(i)), isTrue);
    }
    expect(services.addWaypoint(_stop(4)), isFalse);
    expect(services.waypoints.value.map((s) => s.name).toList(), [
      '경유1',
      '경유2',
      '경유3',
    ]);
  });

  test('경유지 삭제 후에는 다시 추가할 수 있다', () {
    final services = _services();
    addTearDown(services.dispose);

    for (var i = 1; i <= kMaxWaypoints; i++) {
      services.addWaypoint(_stop(i));
    }
    services.removeWaypointAt(0);

    expect(services.addWaypoint(_stop(4)), isTrue);
    expect(services.waypoints.value.map((s) => s.name).toList(), [
      '경유2',
      '경유3',
      '경유4',
    ]);
  });

  test('지도용 경유지 좌표는 경유지 목록과 같이 바뀐다', () {
    final services = _services();
    addTearDown(services.dispose);

    services.addWaypoint(_stop(1));
    services.addWaypoint(_stop(2));
    expect(services.waypointPoints.value, [_stop(1).point, _stop(2).point]);

    services.removeWaypointAt(0);
    expect(services.waypointPoints.value, [_stop(2).point]);

    services.clearWaypoints();
    expect(services.waypoints.value, isEmpty);
    expect(services.waypointPoints.value, isEmpty);
  });
}
