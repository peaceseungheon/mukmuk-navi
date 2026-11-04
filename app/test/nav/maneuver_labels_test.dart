import 'package:flutter_test/flutter_test.dart';
import 'package:mukmuk_app/ffibindings/api/types.dart';
import 'package:mukmuk_app/nav/maneuver_labels.dart';

void main() {
  test('모든 Maneuver가 비어 있지 않은 문구와 아이콘을 가진다', () {
    for (final m in Maneuver.values) {
      expect(maneuverLabel(m), isNotEmpty, reason: m.name);
      expect(maneuverIcon(m).codePoint, isPositive, reason: m.name);
    }
  });

  test('좌회전과 우회전은 서로 다른 문구다', () {
    expect(maneuverLabel(Maneuver.left), isNot(maneuverLabel(Maneuver.right)));
  });
}
