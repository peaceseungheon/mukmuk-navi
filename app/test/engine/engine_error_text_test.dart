import 'package:flutter_test/flutter_test.dart';
import 'package:mukmuk_app/engine/engine_error_text.dart';
import 'package:mukmuk_app/ffibindings/api/types.dart';

void main() {
  test('EngineError 변형마다 사용자 문구를 돌려준다', () {
    final errors = <EngineError>[
      const EngineError.notInitialized(),
      const EngineError.packNotFound(),
      const EngineError.formatMismatch('v2'),
      const EngineError.graphCorrupt('x'),
      const EngineError.searchFailed('x'),
      const EngineError.routingFailed('x'),
      const EngineError.invalidInput('x'),
      const EngineError.internal('x'),
    ];
    for (final e in errors) {
      expect(engineErrorText(e), isNotEmpty, reason: e.toString());
    }
  });

  test('EngineError가 아닌 예외는 일반 문구로 바뀐다', () {
    expect(engineErrorText(StateError('boom')), '알 수 없는 오류가 발생했습니다.');
  });
}
