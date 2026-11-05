import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:mukmuk_app/config.dart';
import 'package:mukmuk_app/engine/engine_error_text.dart';
import 'package:mukmuk_app/engine/navi_engine.dart';
import 'package:mukmuk_app/ffibindings/api/types.dart';
import 'package:mukmuk_app/nav/position_source.dart';
import 'package:mukmuk_app/nav/trip.dart';
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

  /// 활성 구간 번호(0부터). 코어가 안내 중인 구간이다.
  final ValueNotifier<int> activeLeg = ValueNotifier(0);

  /// 아직 도착하지 않은 경유지 좌표(순서대로, 목적지 제외). 지도 마커와 요약에 쓴다.
  final ValueNotifier<List<GeoPoint>> waypoints = ValueNotifier(const []);

  /// 사용자에게 한 번 보여줄 오류 문구. 소비 후 화면이 null로 되돌린다.
  final ValueNotifier<String?> notice = ValueNotifier(null);

  StreamSubscription<NavigationEvent>? _events;
  DateTime? _lastSent;
  bool _inFlight = false;

  /// 지점(경유지들 + 목적지, 마지막 = 목적지)과 구간 경로(_legs[i]: 지점 i-1 → 지점 i).
  List<Stop> _stops = const [];
  List<Route> _legs = const [];
  GeoPoint? _lastSnapped;

  /// 구간 전환 중. 이 동안 위치를 엔진에 보내지 않고 도착 판정을 무시한다.
  bool _switching = false;

  /// 다음 구간 계획이 두 번 다 실패함. 사용자가 안내를 끝내고 다시 계획할 때까지 전환하지 않는다.
  bool _legFailed = false;

  /// 새 구간의 첫 출발 안내는 경유지 도착 문구 뒤에 또 말하지 않는다.
  bool _suppressDepartSpeech = false;

  /// 여정이 시작·종료될 때마다 올라간다. 전환 도중 여정이 바뀌면 그 결과를 버리기 위해 쓴다.
  int _tripSerial = 0;

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

  /// 체인 경로 시작. [legs]는 [stops] 순서의 구간 경로다(legs[i]: 직전 지점 → stops[i]).
  /// 화면에는 남은 구간을 이어 붙인 경로를 보여준다.
  void startTrip(List<Stop> stops, List<Route> legs) {
    assert(stops.length == legs.length, '지점 수와 구간 수가 같아야 한다');
    _tripSerial++;
    _stops = List.of(stops);
    _legs = List.of(legs);
    _lastSnapped = null;
    _switching = false;
    _legFailed = false;
    _suppressDepartSpeech = false;
    activeLeg.value = 0;
    _publishWaypoints();
    final shown = _refreshRoute();
    instruction.value = null;
    offRoute.value = false;
    arrived.value = false;
    position.value = shown.polyline.isEmpty ? null : shown.polyline.first;
  }

  void clearRoute() {
    _tripSerial++;
    _stops = const [];
    _legs = const [];
    _lastSnapped = null;
    _switching = false;
    _legFailed = false;
    _suppressDepartSpeech = false;
    activeLeg.value = 0;
    _publishWaypoints();
    route.value = null;
    instruction.value = null;
    offRoute.value = false;
    arrived.value = false;
    position.value = null;
    _lastSent = null;
  }

  /// 원시 위치를 엔진에 넘긴다. 10Hz 상한을 넘기거나 이전 호출이 끝나지 않았거나 구간 전환 중이면 버린다.
  Future<void> onFix(RawFix fix) async {
    if (route.value == null || _inFlight || _switching) return;
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
      _lastSnapped = snapped.point;
      // 판정 B: 이탈 상태인데 활성 구간 끝 근처면 경유지를 지나친 것으로 보고 다음 구간으로 넘어간다.
      if (snapped.offRoute && _canSwitch && _nearActiveEnd(snapped.point)) {
        await _advanceLeg();
      }
    } catch (e) {
      notice.value = engineErrorText(e);
    } finally {
      _inFlight = false;
    }
  }

  void _onEvent(NavigationEvent event) {
    switch (event) {
      case NavigationEvent_Rerouted(field0: final next):
        if (_acceptsReroute(next)) {
          _legs[activeLeg.value] = next;
          _refreshRoute();
          offRoute.value = false;
        }
      case NavigationEvent_Instruction(field0: final step):
        instruction.value = step;
        final muted = _suppressDepartSpeech && step.maneuver == Maneuver.depart;
        _suppressDepartSpeech = false;
        if (!muted) unawaited(tts.speak(instructionSpeech(step)));
      case NavigationEvent_Arrived():
        if (_hasNextLeg) {
          // 판정 A: 중간 경유지 도착. 늦게 도착한 옛 구간의 신호는 위치로 거른다.
          final snapped = _lastSnapped;
          if (_canSwitch && (snapped == null || _nearActiveEnd(snapped))) {
            unawaited(_advanceLeg());
          }
        } else {
          arrived.value = true;
        }
    }
  }

  /// 다음 구간으로 넘어간다. 경유지 도착 문구를 말하고 다음 구간 경로를 계획한다.
  /// 계획이 실패하면 경유지 기준으로 한 번 더 시도하고, 그래도 실패하면 안내 문구를 남기고 멈춘다.
  Future<void> _advanceLeg() async {
    final serial = _tripSerial;
    final k = activeLeg.value;
    _switching = true;
    try {
      unawaited(
        tts.speak(
          waypointArrivalSpeech(
            k + 1,
            nextIsDestination: k + 1 == _legs.length - 1,
          ),
        ),
      );
      final next = await _planNextLeg(k);
      if (serial != _tripSerial) return;
      _legs[k + 1] = next;
      activeLeg.value = k + 1;
      _publishWaypoints();
      _refreshRoute();
      instruction.value = null;
      offRoute.value = false;
      _suppressDepartSpeech = true;
    } catch (e) {
      if (serial != _tripSerial) return;
      notice.value = '다음 구간 경로를 찾지 못했습니다. ${engineErrorText(e)}';
      _legFailed = true;
    } finally {
      if (serial == _tripSerial) _switching = false;
    }
  }

  Future<Route> _planNextLeg(int k) async {
    final end = _stops[k + 1].point;
    try {
      return await engine.planRoute(
        start: _lastSnapped ?? _stops[k].point,
        end: end,
        profile: TravelProfile.car,
      );
    } catch (_) {
      // 전환 직전 위치에서 실패하면 초기 계획과 같은 질의(경유지 기준)로 한 번 더 시도한다.
      return engine.planRoute(
        start: _stops[k].point,
        end: end,
        profile: TravelProfile.car,
      );
    }
  }

  /// 표시 경로 = 활성 구간부터 끝까지를 이어 붙인 경로. 지난 구간은 뺀다(design 7.2).
  Route _refreshRoute() {
    final shown = combineLegs([
      for (var i = activeLeg.value; i < _legs.length; i++) _legs[i],
    ]);
    route.value = shown;
    return shown;
  }

  /// 활성 구간의 끝(다음 경유지 또는 목적지)부터 목적지 직전까지가 남은 경유지다.
  void _publishWaypoints() {
    waypoints.value = [
      for (var i = activeLeg.value; i < _stops.length - 1; i++) _stops[i].point,
    ];
  }

  bool get _hasNextLeg => activeLeg.value < _legs.length - 1;

  bool get _canSwitch => _hasNextLeg && !_switching && !_legFailed;

  /// 재탐색 결과는 활성 구간의 끝으로 가는 경로일 때만 받는다. 전환 중이거나 끝점이 어긋나면
  /// 전환 전 구간을 기준으로 한 오래된 결과이므로 버린다(design 7.5).
  bool _acceptsReroute(Route next) {
    if (_switching || _legs.isEmpty) return false;
    final current = _legs[activeLeg.value].polyline;
    final fresh = next.polyline;
    return current.isNotEmpty &&
        fresh.isNotEmpty &&
        haversineM(fresh.last, current.last) <= kStaleRerouteToleranceM;
  }

  bool _nearActiveEnd(GeoPoint p) {
    final end = _legs[activeLeg.value].polyline;
    return end.isNotEmpty && haversineM(p, end.last) <= kWaypointPassRadiusM;
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
    activeLeg.dispose();
    waypoints.dispose();
    notice.dispose();
  }
}
