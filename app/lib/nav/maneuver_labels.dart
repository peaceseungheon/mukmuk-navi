import 'package:flutter/material.dart' hide Route;
import 'package:mukmuk_app/ffibindings/api/types.dart';

/// 매뉴버 → 화면 표시 문구. 새 Maneuver가 추가되면 switch가 컴파일 에러로 알려준다.
String maneuverLabel(Maneuver m) => switch (m) {
  Maneuver.depart => '출발',
  Maneuver.left => '좌회전',
  Maneuver.right => '우회전',
  Maneuver.sharpLeft => '급좌회전',
  Maneuver.sharpRight => '급우회전',
  Maneuver.uturn => '유턴',
  Maneuver.straight => '직진',
  Maneuver.mergeLeft => '좌측 합류',
  Maneuver.mergeRight => '우측 합류',
  Maneuver.arrive => '목적지 도착',
};

IconData maneuverIcon(Maneuver m) => switch (m) {
  Maneuver.depart => Icons.trip_origin,
  Maneuver.left => Icons.turn_left,
  Maneuver.right => Icons.turn_right,
  Maneuver.sharpLeft => Icons.turn_sharp_left,
  Maneuver.sharpRight => Icons.turn_sharp_right,
  Maneuver.uturn => Icons.u_turn_left,
  Maneuver.straight => Icons.straight,
  Maneuver.mergeLeft => Icons.merge,
  Maneuver.mergeRight => Icons.merge,
  Maneuver.arrive => Icons.flag,
};
