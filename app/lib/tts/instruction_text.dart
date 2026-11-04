import 'package:mukmuk_app/ffibindings/api/types.dart';
import 'package:mukmuk_app/nav/maneuver_labels.dart';

/// Instruction 이벤트를 읽을 문장으로 만든다. 순수 함수(테스트 대상).
String instructionSpeech(RouteStep step) {
  final road = step.roadName.isEmpty ? '' : '${step.roadName}, ';
  return switch (step.maneuver) {
    Maneuver.depart => '$road경로 안내를 시작합니다.',
    Maneuver.arrive => '목적지에 도착했습니다.',
    _ => '${distanceSpeech(step.distanceM)} 앞에서 $road${maneuverLabel(step.maneuver)}.',
  };
}

/// 거리 낭독 문구. 1km 미만은 미터 단위, 이상은 킬로미터(소수 첫째 자리).
String distanceSpeech(double meters) {
  if (meters < 1000) {
    final rounded = (meters / 10).round() * 10;
    return '$rounded미터';
  }
  final km = (meters / 100).round() / 10;
  return '${km.toStringAsFixed(1)}킬로미터';
}
