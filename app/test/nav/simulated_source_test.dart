import 'package:flutter_test/flutter_test.dart';
import 'package:mukmuk_app/ffibindings/api/types.dart';
import 'package:mukmuk_app/nav/position_source.dart';

void main() {
  test('모의 주행은 정점을 순서대로 흘리고 끝나면 닫힌다', () async {
    const polyline = [
      GeoPoint(lat: 36.35, lon: 127.38),
      GeoPoint(lat: 36.36, lon: 127.38),
      GeoPoint(lat: 36.37, lon: 127.38),
    ];
    final source = SimulatedPositionSource(
      polyline,
      interval: const Duration(milliseconds: 1),
    );
    final fixes = await source.fixes.toList();

    expect(fixes.map((f) => f.point.lat).toList(), [36.35, 36.36, 36.37]);
    expect(fixes.every((f) => f.speedMps == 14), isTrue);
  });

  test('북쪽으로 가는 구간의 방위각은 0도 근처다', () async {
    const polyline = [
      GeoPoint(lat: 36.35, lon: 127.38),
      GeoPoint(lat: 36.36, lon: 127.38),
    ];
    final fixes = await SimulatedPositionSource(
      polyline,
      interval: const Duration(milliseconds: 1),
    ).fixes.toList();

    expect(fixes.first.headingDeg, closeTo(0, 1e-9));
  });
}
