import 'package:mukmuk_app/ffibindings/api/types.dart';

/// FFI 실패를 사용자에게 보여줄 한국어 문구로 바꾼다.
String engineErrorText(Object error) {
  if (error is! EngineError) {
    return '알 수 없는 오류가 발생했습니다.';
  }
  return switch (error) {
    EngineError_NotInitialized() => '지도 데이터를 아직 불러오지 못했습니다.',
    EngineError_PackNotFound() => '데이터 팩을 찾을 수 없습니다. 팩 경로를 확인하세요.',
    EngineError_FormatMismatch() => '데이터 팩 버전이 앱과 맞지 않습니다.',
    EngineError_GraphCorrupt() => '도로 데이터가 손상되었습니다.',
    EngineError_SearchFailed() => '검색에 실패했습니다.',
    EngineError_RoutingFailed() => '경로를 찾지 못했습니다.',
    EngineError_InvalidInput() => '입력값을 확인하세요.',
    EngineError_Internal() => '내부 오류가 발생했습니다.',
  };
}
