# 검증 요약 (사람) — 회차 2 (2026-11-04)

- 범위: rust-core 게이트·KPI·FFI 계약, data-pipeline 샘플 팩 스모크, flutter-app(F1~F10) 정적 게이트. 기준 커밋 `main` `40a47e8`.
- 결과: **FAIL 0건**. 회차 1의 flutter-app `BLOCKED-ENV`는 SDK 업그레이드로 해소. 상세는 [`docs/agent/verify.md`](../agent/verify.md) 회차 2 절.

## KPI 4종

| KPI | 목표 | 측정값 | 판정 |
| --- | --- | --- | --- |
| 메모리 | 총 RAM 150MB 이하, 4시간 주행 누수 0% | 코어 호스트 RSS +0.24MB/600회 (합성 400노드) | 코어 통과, 실기기 MANUAL(승인) |
| 재탐색 | 1초 이내 | 평균 26µs (호스트·합성 그래프, 300회) | 호스트 통과, 실기기·전국 MANUAL(승인) |
| 프레임 | 드랍 1% 미만 (60fps) | 미측정 | MANUAL(승인) |
| 검색 | 반경 50km, 0.5초 | 평균 1.0ms (픽스처 팩·반경 10km, 회차 1은 0.78ms) | 샘플 규모 통과, 전국 50km MANUAL(승인) |

## 이번 회차 확인한 것

- Rust: 포맷·clippy(`-D warnings`)·전체 테스트 41개 모두 통과. FFI 5개 함수가 설계 2.2절과 Dart 바인딩에서 일치.
- 데이터: 샘플 팩을 Rust 코어가 직접 열어 경로 1건·검색 1건 성공. manifest 해시 3/3 일치.
- Flutter: `flutter analyze` 이슈 0건, `flutter test` 29개 전부 통과. 생성 바인딩 직접 호출은 `main.dart` 초기화 1곳뿐.
- Git: 워킹트리 clean, 검증 대상 커밋 모두 `main`에 있음. `main`은 `origin/main`보다 16커밋 앞서 있으며 push는 하지 않았다.

## 아직 사람이 확인해야 할 항목 (MANUAL 9건)

1. 실기기/에뮬레이터에서 지도 렌더·pan/zoom(F2), 검색 호출·반경 필터(F3), 경로 선 렌더(F4), 실제 주행 위치 갱신(F5), 재탐색 이벤트(F6), TTS 발화(F7), 위치 서비스 토글 안내(F9).
2. F1(에뮬레이터 `init_engine`)과 F10(스타일 경고 0건)은 직전 기록을 인용했고 이번 회차에 재실행하지 않았다.
3. KPI 실측: `flutter run --profile` 후 DevTools로 프레임 드랍, 4시간 모의주행 전후 `adb shell dumpsys meminfo <pkg>`.

## 판정

코어·데이터 파이프라인과 Flutter 정적 게이트는 실행 결과로 통과했다. KPI 실기기·전국 규모 수치는 아직 측정되지 않았고, 이 항목은 승인된 MANUAL로 남긴다. 앱 기능의 실기기 확인이 끝나면 배포 준비(4단계) 진행을 검토할 수 있다.
