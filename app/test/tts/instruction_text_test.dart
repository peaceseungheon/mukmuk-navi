import 'package:flutter_test/flutter_test.dart';
import 'package:mukmuk_app/ffibindings/api/types.dart';
import 'package:mukmuk_app/tts/instruction_text.dart';

import '../support/fakes.dart';

void main() {
  test('미터 거리는 10m 단위로 낭독한다', () {
    expect(distanceSpeech(296), '300미터');
    expect(distanceSpeech(42), '40미터');
  });

  test('1km 이상은 킬로미터 소수 첫째 자리로 낭독한다', () {
    expect(distanceSpeech(1000), '1.0킬로미터');
    expect(distanceSpeech(2549), '2.5킬로미터');
  });

  test('회전 안내는 거리·도로명·매뉴버를 포함한다', () {
    final text = instructionSpeech(
      fakeStep(maneuver: Maneuver.right, roadName: '대덕대로', distanceM: 500),
    );
    expect(text, '500미터 앞에서 대덕대로, 우회전.');
  });

  test('도로명이 없으면 도로명 부분을 생략한다', () {
    final text = instructionSpeech(fakeStep(maneuver: Maneuver.straight));
    expect(text, '300미터 앞에서 직진.');
  });

  test('출발과 도착 문장은 거리를 말하지 않는다', () {
    expect(
      instructionSpeech(fakeStep(maneuver: Maneuver.depart, roadName: '가')),
      '가, 경로 안내를 시작합니다.',
    );
    expect(
      instructionSpeech(fakeStep(maneuver: Maneuver.arrive)),
      '목적지에 도착했습니다.',
    );
  });
}
