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

  test('다음 지점이 경유지면 다음 경유지로 안내한다는 발화를 만든다', () {
    expect(
      waypointArrivalSpeech(1, nextIsDestination: false),
      '경유지 1에 도착했습니다. 다음 경유지로 안내합니다.',
    );
  });

  test('다음 지점이 목적지면 목적지로 안내한다는 발화를 만든다', () {
    expect(
      waypointArrivalSpeech(2, nextIsDestination: true),
      '경유지 2에 도착했습니다. 목적지로 안내합니다.',
    );
  });
}
