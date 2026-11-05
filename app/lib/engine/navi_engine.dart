import 'package:mukmuk_app/ffibindings/api.dart' as ffi;
import 'package:mukmuk_app/ffibindings/api/types.dart';

/// Rust 코어 호출 경계. UI·컨트롤러는 이 인터페이스에만 의존한다(테스트에서 가짜 구현으로 대체).
abstract interface class NaviEngine {
  Future<EngineInfo> init(String packDir);

  Future<List<PoiResult>> searchPoi({
    required String query,
    required GeoPoint center,
    required double radiusKm,
    required int limit,
  });

  /// 지도 탭 지점 주변 장소(거리순). 설계 2.2절에 추가된 계약이다.
  Future<List<PoiResult>> nearbyPoi({
    required GeoPoint center,
    required double radiusKm,
    required int limit,
  });

  Future<Route> planRoute({
    required GeoPoint start,
    required GeoPoint end,
    required TravelProfile profile,
  });

  /// 프로세스당 한 번만 호출한다. 이후 이벤트가 이 스트림으로 들어온다.
  Stream<NavigationEvent> subscribe();

  Future<SnappedPosition> updatePosition({
    required GeoPoint pos,
    required double speedMps,
    required double headingDeg,
    required int tMs,
  });
}

/// design.md 2.2절 FRB 생성 바인딩을 그대로 위임한다. 연산 로직은 두지 않는다.
final class FrbNaviEngine implements NaviEngine {
  const FrbNaviEngine();

  @override
  Future<EngineInfo> init(String packDir) => ffi.initEngine(packDir: packDir);

  @override
  Future<List<PoiResult>> searchPoi({
    required String query,
    required GeoPoint center,
    required double radiusKm,
    required int limit,
  }) => ffi.searchPoi(
    query: query,
    center: center,
    radiusKm: radiusKm,
    limit: limit,
  );

  @override
  Future<List<PoiResult>> nearbyPoi({
    required GeoPoint center,
    required double radiusKm,
    required int limit,
  }) => ffi.nearbyPoi(center: center, radiusKm: radiusKm, limit: limit);

  @override
  Future<Route> planRoute({
    required GeoPoint start,
    required GeoPoint end,
    required TravelProfile profile,
  }) => ffi.planRoute(start: start, end: end, profile: profile);

  @override
  Stream<NavigationEvent> subscribe() => ffi.subscribeNavigation();

  @override
  Future<SnappedPosition> updatePosition({
    required GeoPoint pos,
    required double speedMps,
    required double headingDeg,
    required int tMs,
  }) => ffi.updatePosition(
    pos: pos,
    speedMps: speedMps,
    headingDeg: headingDeg,
    tMs: BigInt.from(tMs),
  );
}
