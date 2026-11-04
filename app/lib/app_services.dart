import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart' show PermissionDeniedException;
import 'package:mukmuk_app/config.dart';
import 'package:mukmuk_app/engine/navi_engine.dart';
import 'package:mukmuk_app/ffibindings/api/types.dart';
import 'package:mukmuk_app/nav/navigation_controller.dart';
import 'package:mukmuk_app/nav/position_source.dart';
import 'package:mukmuk_app/tts/tts_speaker.dart';

/// 엔진 초기화 후 화면이 공유하는 서비스 묶음.
final class AppServices {
  AppServices({
    required this.engine,
    required this.info,
    required this.tts,
    required this.ttsAvailable,
    required this.nav,
  });

  final NaviEngine engine;
  final EngineInfo info;
  final TtsSpeaker tts;
  final bool ttsAvailable;
  final NavigationController nav;

  /// 최근 GPS 위치. 권한이 없거나 아직 수신 전이면 null.
  final ValueNotifier<GeoPoint?> lastGps = ValueNotifier(null);
  StreamSubscription<RawFix>? _gpsSub;

  /// 위치 서비스 꺼짐·권한 거부 등 홈 화면이 한 번 보여줄 안내. 소비 후 null로 되돌린다.
  final ValueNotifier<String?> gpsNotice = ValueNotifier(null);

  GeoPoint get origin =>
      lastGps.value ??
      const GeoPoint(lat: kDefaultOriginLat, lon: kDefaultOriginLon);

  Future<void> dispose() async {
    await _gpsSub?.cancel();
    lastGps.dispose();
    gpsNotice.dispose();
    await nav.dispose();
  }
}

Future<AppServices> bootServices() async {
  if (kPackDir.isEmpty) {
    throw StateError('MUKMUK_PACK_DIR가 설정되지 않았습니다. --dart-define으로 팩 경로를 주세요.');
  }
  const engine = FrbNaviEngine();
  final info = await engine.init(kPackDir);

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
