import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:mukmuk_app/config.dart';
import 'package:mukmuk_app/engine/engine_error_text.dart';
import 'package:mukmuk_app/engine/navi_engine.dart';
import 'package:mukmuk_app/ffibindings/api/types.dart';
import 'package:mukmuk_app/nav/position_source.dart';
import 'package:mukmuk_app/tts/instruction_text.dart';
import 'package:mukmuk_app/tts/tts_speaker.dart';

/// 길 안내 상태 보관소. 화면은 각 ValueNotifier만 구독해 필요한 부분만 리빌드한다.
/// subscribe_navigation은 엔진당 1회만 호출해야 하므로 앱 수명 동안 하나를 공유한다.
class NavigationController {
  NavigationController({
    required this.engine,
    required this.tts,
    this.now = DateTime.now,
  });

  final NaviEngine engine;
  final TtsSpeaker tts;
  final DateTime Function() now;

  final ValueNotifier<Route?> route = ValueNotifier(null);
  final ValueNotifier<GeoPoint?> position = ValueNotifier(null);
  final ValueNotifier<RouteStep?> instruction = ValueNotifier(null);
  final ValueNotifier<bool> offRoute = ValueNotifier(false);
  final ValueNotifier<bool> arrived = ValueNotifier(false);

  /// 사용자에게 한 번 보여줄 오류 문구. 소비 후 화면이 null로 되돌린다.
  final ValueNotifier<String?> notice = ValueNotifier(null);

  StreamSubscription<NavigationEvent>? _events;
  DateTime? _lastSent;
  bool _inFlight = false;

  /// 이벤트 구독을 한 번만 시작한다. 이후 호출은 무시한다.
  Future<void> ensureSubscribed() async {
    if (_events != null) return;
    try {
      _events = engine.subscribe().listen(
        _onEvent,
        onError: (Object e) => notice.value = engineErrorText(e),
      );
    } catch (e) {
      notice.value = engineErrorText(e);
    }
  }

  void startRoute(Route next) {
    route.value = next;
    instruction.value = null;
    offRoute.value = false;
    arrived.value = false;
    position.value = next.polyline.isEmpty ? null : next.polyline.first;
  }

  void clearRoute() {
    route.value = null;
    instruction.value = null;
    offRoute.value = false;
    arrived.value = false;
    position.value = null;
    _lastSent = null;
  }

  /// 원시 위치를 엔진에 넘긴다. 10Hz 상한을 넘기거나 이전 호출이 끝나지 않았으면 버린다.
  Future<void> onFix(RawFix fix) async {
    if (route.value == null || _inFlight) return;
    final current = now();
    final last = _lastSent;
    if (last != null && current.difference(last) < kPositionMinInterval) return;
    _lastSent = current;
    _inFlight = true;
    try {
      final snapped = await engine.updatePosition(
        pos: fix.point,
        speedMps: fix.speedMps,
        headingDeg: fix.headingDeg,
        tMs: fix.tMs,
      );
      position.value = snapped.point;
      offRoute.value = snapped.offRoute;
    } catch (e) {
      notice.value = engineErrorText(e);
    } finally {
      _inFlight = false;
    }
  }

  void _onEvent(NavigationEvent event) {
    switch (event) {
      case NavigationEvent_Rerouted(field0: final next):
        route.value = next;
        offRoute.value = false;
      case NavigationEvent_Instruction(field0: final step):
        instruction.value = step;
        unawaited(tts.speak(instructionSpeech(step)));
      case NavigationEvent_Arrived():
        arrived.value = true;
    }
  }

  Future<void> dispose() async {
    await _events?.cancel();
    _events = null;
    await tts.stop();
    route.dispose();
    position.dispose();
    instruction.dispose();
    offRoute.dispose();
    arrived.dispose();
    notice.dispose();
  }
}
