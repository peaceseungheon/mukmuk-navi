/// 화면 표시용 거리 문구. 1km 미만은 미터, 이상은 킬로미터(소수 첫째 자리).
String formatDistanceM(double meters) {
  if (meters < 1000) return '${meters.round()}m';
  return '${(meters / 1000).toStringAsFixed(1)}km';
}

/// 예상 소요 시간 문구. 초 단위 입력을 분 단위로 올림한다(최소 1분).
String formatDurationS(double seconds) {
  final minutes = (seconds / 60).ceil().clamp(1, 1 << 30);
  if (minutes < 60) return '$minutes분';
  final h = minutes ~/ 60;
  final m = minutes % 60;
  return m == 0 ? '$h시간' : '$h시간 $m분';
}
