import 'dart:async';

import 'package:mukmuk_app/engine/navi_engine.dart';
import 'package:mukmuk_app/ffibindings/api/types.dart';
import 'package:mukmuk_app/tts/tts_speaker.dart';

/// Rust 코어 없이 컨트롤러·화면을 검증하기 위한 가짜 엔진.
class FakeNaviEngine implements NaviEngine {
  final StreamController<NavigationEvent> events =
      StreamController<NavigationEvent>.broadcast();

  final List<({double speed, double heading, int tMs})> positionCalls = [];
  final List<PoiResult> poiResults = [];
  SnappedPosition Function(GeoPoint pos)? onUpdate;
  Object? updateError;
  int subscribeCount = 0;
  Completer<void>? updateGate;

  @override
  Future<EngineInfo> init(String packDir) async => fakeInfo();

  @override
  Future<List<PoiResult>> searchPoi({
    required String query,
    required GeoPoint center,
    required double radiusKm,
    required int limit,
  }) async => poiResults;

  @override
  Future<Route> planRoute({
    required GeoPoint start,
    required GeoPoint end,
    required TravelProfile profile,
  }) async => fakeRoute([start, end]);

  @override
  Stream<NavigationEvent> subscribe() {
    subscribeCount++;
    return events.stream;
  }

  @override
  Future<SnappedPosition> updatePosition({
    required GeoPoint pos,
    required double speedMps,
    required double headingDeg,
    required int tMs,
  }) async {
    positionCalls.add((speed: speedMps, heading: headingDeg, tMs: tMs));
    final gate = updateGate;
    if (gate != null) await gate.future;
    final error = updateError;
    if (error != null) throw error;
    final handler = onUpdate;
    if (handler != null) return handler(pos);
    return SnappedPosition(
      point: pos,
      roadId: BigInt.zero,
      distanceToRouteM: 0,
      offRoute: false,
    );
  }
}

class FakeTtsSpeaker implements TtsSpeaker {
  final List<String> spoken = [];
  bool available = true;
  Object? initError;

  @override
  Future<bool> init() async {
    final error = initError;
    if (error != null) throw error;
    return available;
  }

  @override
  Future<void> speak(String text) async {
    if (available) spoken.add(text);
  }

  @override
  Future<void> stop() async {}
}

EngineInfo fakeInfo() => EngineInfo(
  packVersion: '2026.11',
  osmDate: '2026-11-02',
  formatVersion: 1,
  nodeCount: BigInt.zero,
  poiCount: BigInt.zero,
  bbox: const BBox(minLon: 124, minLat: 33, maxLon: 132, maxLat: 39),
);

Route fakeRoute(List<GeoPoint> polyline, {List<RouteStep> steps = const []}) =>
    Route(
      polyline: polyline,
      steps: steps,
      totalDistanceM: 1200,
      totalDurationS: 180,
    );

RouteStep fakeStep({
  Maneuver maneuver = Maneuver.left,
  String roadName = '',
  double distanceM = 300,
}) => RouteStep(
  maneuver: maneuver,
  roadName: roadName,
  point: const GeoPoint(lat: 36.35, lon: 127.38),
  distanceM: distanceM,
  durationS: 20,
);
