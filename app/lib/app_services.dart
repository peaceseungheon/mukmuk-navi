import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart' show PermissionDeniedException;
import 'package:mukmuk_app/config.dart';
import 'package:mukmuk_app/engine/navi_engine.dart';
import 'package:mukmuk_app/ffibindings/api/types.dart';
import 'package:mukmuk_app/nav/navigation_controller.dart';
import 'package:mukmuk_app/nav/position_source.dart';
import 'package:mukmuk_app/nav/trip.dart';
import 'package:mukmuk_app/packs/pack_fetcher.dart';
import 'package:mukmuk_app/packs/pack_update_controller.dart';
import 'package:mukmuk_app/packs/pack_updater.dart';
import 'package:path_provider/path_provider.dart';
import 'package:mukmuk_app/tts/tts_speaker.dart';

/// 엔진 초기화 후 화면이 공유하는 서비스 묶음.
final class AppServices {
  AppServices({
    required this.engine,
    required this.info,
    required this.tts,
    required this.ttsAvailable,
    required this.nav,
    this.packDir = kPackDir,
    this.packUpdate,
  });

  final NaviEngine engine;
  final EngineInfo info;
  final TtsSpeaker tts;
  final bool ttsAvailable;
  final NavigationController nav;

  /// 엔진이 연 활성 팩 디렉터리(지도 mbtiles 경로의 기준).
  final String packDir;

  /// 팩 업데이트 컨트롤러. MUKMUK_PACK_URL이 없으면 null(기능 숨김).
  final PackUpdateController? packUpdate;

  /// 최근 GPS 위치. 권한이 없거나 아직 수신 전이면 null.
  final ValueNotifier<GeoPoint?> lastGps = ValueNotifier(null);
  StreamSubscription<RawFix>? _gpsSub;

  /// 위치 서비스 꺼짐·권한 거부 등 홈 화면이 한 번 보여줄 안내. 소비 후 null로 되돌린다.
  final ValueNotifier<String?> gpsNotice = ValueNotifier(null);

  /// 지도 탭으로 사용자가 지정한 출발지. null이면 GPS 위치를 쓴다.
  final ValueNotifier<GeoPoint?> pickedOrigin = ValueNotifier(null);

  /// 목적지 전에 들를 경유지(최대 [kMaxWaypoints]). 추가는 끝에, 삭제는 칩의 ×로 한다.
  final ValueNotifier<List<Stop>> waypoints = ValueNotifier(const []);

  /// 경유지를 끝에 추가한다. 이미 [kMaxWaypoints]개면 추가하지 않고 false를 돌려준다.
  bool addWaypoint(Stop stop) {
    final current = waypoints.value;
    if (current.length >= kMaxWaypoints) return false;
    waypoints.value = [...current, stop];
    return true;
  }

  void removeWaypointAt(int index) {
    waypoints.value = [...waypoints.value]..removeAt(index);
  }

  /// 경로·검색 기준점: 지정한 출발지 → GPS 위치 → 기본값(대전 시청) 순서.
  GeoPoint get origin =>
      pickedOrigin.value ??
      lastGps.value ??
      const GeoPoint(lat: kDefaultOriginLat, lon: kDefaultOriginLon);

  Future<void> dispose() async {
    await _gpsSub?.cancel();
    pickedOrigin.dispose();
    waypoints.dispose();
    lastGps.dispose();
    gpsNotice.dispose();
    packUpdate?.dispose();
    await nav.dispose();
  }
}

/// 사용할 수 있는 팩이 없지만 [kPackUrl]이 있어 내려받을 수 있는 상태.
class PackMissingException implements Exception {
  const PackMissingException(this.supportDir);

  final Directory supportDir;
}

Future<AppServices> bootServices() async {
  const engine = FrbNaviEngine();
  Directory? supportDir;
  String? packDir;
  EngineInfo? info;
  if (kPackUrl.isNotEmpty) {
    // 다운로드된 팩이 있고 엔진 검증을 통과하면 그것을 쓴다. 실패하면 kPackDir로 되돌아간다.
    supportDir = await getApplicationSupportDirectory();
    final downloaded = '${supportDir.path}/pack';
    if (await File('$downloaded/manifest.json').exists()) {
      try {
        info = await engine.init(downloaded);
        packDir = downloaded;
      } catch (_) {}
    }
  }
  if (info == null) {
    try {
      if (kPackDir.isEmpty) {
        throw StateError(
          'MUKMUK_PACK_DIR가 설정되지 않았습니다. --dart-define으로 팩 경로를 주세요.',
        );
      }
      info = await engine.init(kPackDir);
      packDir = kPackDir;
    } catch (_) {
      // 팩이 없고 내려받을 주소가 있으면 첫 실행 다운로드 화면으로 넘긴다.
      if (supportDir != null) throw PackMissingException(supportDir);
      rethrow;
    }
  }

  final tts = FlutterTtsSpeaker();
  final ttsAvailable = await probeTtsAvailable(tts);

  final nav = NavigationController(engine: engine, tts: tts);
  await nav.ensureSubscribed();

  final services = AppServices(
    engine: engine,
    info: info,
    tts: tts,
    ttsAvailable: ttsAvailable,
    nav: nav,
    packDir: packDir!,
    packUpdate: supportDir == null
        ? null
        : PackUpdateController(
            activeDir: packDir,
            updater: PackUpdater(
              baseDir: supportDir,
              fetcher: HttpPackFetcher(kPackUrl),
              isWifi: isOnWifi,
              reinit: engine.init,
            ),
          ),
  );
  if (await GeolocatorPositionSource.ensurePermission()) {
    services._gpsSub = listenFixes(
      const GeolocatorPositionSource().fixes,
      (fix) => services.lastGps.value = fix.point,
      (text) => services.gpsNotice.value = text,
    );
  } else {
    services.gpsNotice.value = locationErrorText(
      const PermissionDeniedException('location unavailable'),
    );
  }
  return services;
}
