import 'dart:async';
import 'dart:math' as math;

import 'package:geolocator/geolocator.dart';
import 'package:mukmuk_app/config.dart';
import 'package:mukmuk_app/ffibindings/api/types.dart';

/// 원시 위치 한 건. update_position 입력과 같은 단위(도, m/s, 도, ms).
final class RawFix {
  const RawFix({
    required this.point,
    required this.speedMps,
    required this.headingDeg,
    required this.tMs,
  });

  final GeoPoint point;
  final double speedMps;
  final double headingDeg;
  final int tMs;
}

/// 위치 스트림 오류를 사용자 안내 문구로 바꾼다.
String locationErrorText(Object error) => switch (error) {
  LocationServiceDisabledException() => '기기의 위치 서비스가 꺼져 있습니다. 켜면 현재 위치를 사용할 수 있습니다.',
  PermissionDeniedException() => '위치 권한이 거부되었습니다. 설정에서 허용하면 현재 위치를 사용할 수 있습니다.',
  _ => '현재 위치를 가져올 수 없습니다.',
};

/// [fixes]를 구독한다. 스트림 오류는 unhandled로 새지 않고 [onNotice]에 안내 문구로 전달한다.
StreamSubscription<RawFix> listenFixes(
  Stream<RawFix> fixes,
  void Function(RawFix) onFix,
  void Function(String) onNotice,
) => fixes.listen(onFix, onError: (Object e) => onNotice(locationErrorText(e)));

/// 위치 공급원. 실 GPS 또는 모의 주행.
abstract interface class PositionSource {
  Stream<RawFix> get fixes;
}

/// 위치 권한·서비스를 확인하고 GPS 스트림을 제공한다.
final class GeolocatorPositionSource implements PositionSource {
  const GeolocatorPositionSource();

  /// 권한이 허용되었으면 true. 거부 시 호출 측이 안내한다.
  static Future<bool> ensurePermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) return false;
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    return permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;
  }

  @override
  Stream<RawFix> get fixes => Geolocator.getPositionStream(
    locationSettings: const LocationSettings(
      accuracy: LocationAccuracy.best,
      distanceFilter: 0,
    ),
  ).map(
    (p) => RawFix(
      point: GeoPoint(lat: p.latitude, lon: p.longitude),
      speedMps: p.speed < 0 ? 0 : p.speed,
      headingDeg: p.heading,
      tMs: p.timestamp.millisecondsSinceEpoch,
    ),
  );
}

/// 경로 정점을 순서대로 흘려보내는 모의 주행. 정점 간격 기반 속도 보간은 하지 않는다
/// (고정 속도 [kSimulationSpeedMps]로 보고). 속도 보간이 필요해지면 그때 추가한다.
final class SimulatedPositionSource implements PositionSource {
  SimulatedPositionSource(
    this.polyline, {
    this.interval = kSimulationInterval,
    this.now = DateTime.now,
  });

  final List<GeoPoint> polyline;
  final Duration interval;
  final DateTime Function() now;

  @override
  Stream<RawFix> get fixes {
    late StreamController<RawFix> controller;
    Timer? timer;
    var index = 0;

    void tick() {
      if (index >= polyline.length) {
        timer?.cancel();
        unawaited(controller.close());
        return;
      }
      final here = polyline[index];
      final next = index + 1 < polyline.length
          ? polyline[index + 1]
          : here;
      controller.add(
        RawFix(
          point: here,
          speedMps: kSimulationSpeedMps,
          headingDeg: _bearingDeg(here, next),
          tMs: now().millisecondsSinceEpoch,
        ),
      );
      index++;
    }

    controller = StreamController<RawFix>(
      onListen: () {
        tick();
        timer = Timer.periodic(interval, (_) => tick());
      },
      onCancel: () => timer?.cancel(),
    );
    return controller.stream;
  }
}

/// 두 점 사이 진북 기준 방위각(0~360). 짧은 거리 근사라 Dart에서 계산해도 비용이 없다.
double _bearingDeg(GeoPoint a, GeoPoint b) {
  if (a.lat == b.lat && a.lon == b.lon) return 0;
  final dLat = b.lat - a.lat;
  final dLon = (b.lon - a.lon) * math.cos(a.lat * math.pi / 180);
  final deg = math.atan2(dLon, dLat) * 180 / math.pi;
  return (deg + 360) % 360;
}
