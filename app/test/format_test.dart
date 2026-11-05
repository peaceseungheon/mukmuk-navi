import 'package:flutter_test/flutter_test.dart';
import 'package:mukmuk_app/format.dart';

void main() {
  test('거리는 1km 미만 m, 이상 km로 표시한다', () {
    expect(formatDistanceM(120.4), '120m');
    expect(formatDistanceM(1250), '1.3km');
  });

  test('소요 시간은 올림한 분과 시간으로 표시한다', () {
    expect(formatDurationS(30), '1분');
    expect(formatDurationS(200), '4분');
    expect(formatDurationS(3900), '1시간 5분');
    expect(formatDurationS(7200), '2시간');
  });

  test('주행 요약은 남은 경유지가 있을 때만 경유 문구를 앞에 붙인다', () {
    expect(
      tripSummaryText(remainingWaypoints: 0, distanceM: 1250, durationS: 200),
      '1.3km · 4분',
    );
    expect(
      tripSummaryText(remainingWaypoints: 2, distanceM: 1250, durationS: 200),
      '경유 2곳 남음 · 1.3km · 4분',
    );
  });
}
