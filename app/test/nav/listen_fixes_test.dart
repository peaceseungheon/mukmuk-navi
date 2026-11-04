import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mukmuk_app/ffibindings/api/types.dart';
import 'package:mukmuk_app/nav/position_source.dart';

void main() {
  test('위치 서비스 꺼짐 예외는 안내 문구로 전달되고 이후 위치도 계속 받는다', () async {
    final controller = StreamController<RawFix>();
    final fixes = <RawFix>[];
    final notices = <String>[];
    final sub = listenFixes(controller.stream, fixes.add, notices.add);

    controller.addError(const LocationServiceDisabledException());
    controller.add(
      const RawFix(
        point: GeoPoint(lat: 36.3, lon: 127.4),
        speedMps: 1,
        headingDeg: 0,
        tMs: 1,
      ),
    );
    await pumpEventQueue();

    expect(notices, hasLength(1));
    expect(notices.single, contains('위치 서비스'));
    expect(fixes, hasLength(1));
    await sub.cancel();
    await controller.close();
  });

  test('권한 거부 예외는 권한 안내, 그 외는 일반 문구', () {
    expect(
      locationErrorText(const PermissionDeniedException('x')),
      contains('권한'),
    );
    expect(locationErrorText(StateError('x')), '현재 위치를 가져올 수 없습니다.');
  });
}
