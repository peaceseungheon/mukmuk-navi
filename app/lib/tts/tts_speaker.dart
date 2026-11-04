import 'package:flutter_tts/flutter_tts.dart';

/// 음성 안내 출력. 구현은 네트워크를 쓰지 않는 플랫폼 기본 엔진만 사용한다.
abstract interface class TtsSpeaker {
  /// 오프라인 ko-KR 음성을 찾아 설정한다. 없으면 false(발화 생략, design.md 6절 5번 미결).
  Future<bool> init();

  Future<void> speak(String text);

  Future<void> stop();
}

const String kSpeechLocale = 'ko-KR';

final class FlutterTtsSpeaker implements TtsSpeaker {
  FlutterTtsSpeaker([FlutterTts? tts]) : _tts = tts ?? FlutterTts();

  final FlutterTts _tts;
  bool _available = false;

  @override
  Future<bool> init() async {
    _available = false;
    final voices = await _tts.getVoices;
    if (voices is! List) return false;
    for (final raw in voices) {
      if (raw is! Map) continue;
      final locale = '${raw['locale'] ?? ''}';
      // Android: network_required "1"이면 네트워크 음성이므로 제외한다.
      final networkRequired = '${raw['network_required'] ?? '1'}' == '1';
      if (!locale.toLowerCase().startsWith('ko') || networkRequired) continue;
      await _tts.setVoice({
        'name': '${raw['name']}',
        'locale': locale,
      });
      await _tts.setLanguage(kSpeechLocale);
      await _tts.awaitSpeakCompletion(false);
      _available = true;
      return true;
    }
    return false;
  }

  @override
  Future<void> speak(String text) async {
    if (!_available) return;
    await _tts.speak(text);
  }

  @override
  Future<void> stop() => _tts.stop();
}
