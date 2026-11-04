import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mukmuk_app/tts/tts_install_banner.dart';
import 'package:mukmuk_app/tts/tts_speaker.dart';

import '../support/fakes.dart';

Future<void> _pump(WidgetTester tester, FakeTtsSpeaker tts) async {
  final available = await probeTtsAvailable(tts);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: TtsInstallBanner(ttsAvailable: available)),
    ),
  );
}

void main() {
  testWidgets('음성이 있으면 배너가 없다', (tester) async {
    await _pump(tester, FakeTtsSpeaker());
    expect(find.text(kTtsInstallBannerText), findsNothing);
  });

  testWidgets('음성이 없으면 배너가 보이고 닫으면 사라진다', (tester) async {
    await _pump(tester, FakeTtsSpeaker()..available = false);
    expect(find.text(kTtsInstallBannerText), findsOneWidget);
    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();
    expect(find.text(kTtsInstallBannerText), findsNothing);
  });

  testWidgets('탐색 예외도 배너를 띄운다', (tester) async {
    await _pump(tester, FakeTtsSpeaker()..initError = StateError('boom'));
    expect(find.text(kTtsInstallBannerText), findsOneWidget);
  });
}
