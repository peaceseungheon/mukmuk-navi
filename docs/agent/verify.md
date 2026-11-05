# 검증 결과 (agent)

- 기준: `docs/agent/design.md`(승인 2026-11-03, 포맷 v1), `docs/agent/tasks.md`
- 환경: Windows 10 (Git Bash) / rustc 1.96.1 / WSL2 Ubuntu / Flutter 3.22.1 / Dart 3.4.1
- 이번 회차 미수행: `pipeline/build_all --skip-extract` 재실행(기존 `data/sample/` 산출물을 현재 실행으로 검증). 직전 로그 `data/work/build_all_final.log`에 smoke OK·zip OK 기록.

## 회차 1 (2026-11-04)

### rust-core
- [PASS] 포맷 검사 — area: rust-core — `cd core && cargo fmt --check` — exit 0, diff 없음
- [PASS] 정적 분석 — area: rust-core — `cd core && cargo clippy --workspace --all-targets -- -D warnings` — `Finished dev profile ... in 1.22s`, exit 0
- [PASS] 전체 테스트 — area: rust-core — `cd core && cargo test --workspace` — 41 passed / 0 failed (unit 34, bridge 3, compiler 2, kpi 1, zero_copy 1)
- [PASS] R2 zero-copy 힙 상한 — area: rust-core — `cargo test -p mukmuk-core --test zero_copy` — `heap_allocations_do_not_scale_with_graph_file_size ... ok`
- [PASS] FFI 계약 대조 — area: rust-core — `docs/agent/design.md` 2.1/2.2 ↔ `core/bridge/src/api/{mod,types}.rs` ↔ `app/lib/ffibindings/api.dart` — 5개 함수 시그니처·타입·Dart camelCase(`initEngine`/`searchPoi`/`planRoute`/`subscribeNavigation`/`updatePosition`) 일치, `ffi_contract_flow ... ok`. 의존 버전도 설계와 일치(FRB 2.13.0, rkyv 0.8.18, memmap2 0.9.12, rusqlite 0.41.1, fast_paths 1.0.0)
- [PASS] R12 KPI 하네스 실행 — area: rust-core — `cargo test -p mukmuk-core --release --test kpi -- --nocapture` — `KPI reroute avg: 25.353µs`, `KPI search avg: 782.509µs`, `RSS delta=245760`

### data-pipeline
- [PASS] manifest 무결성 — area: data-pipeline — `sha256sum data/sample/{map/korea.mbtiles,graph/korea.graph.bin,poi/korea.poi.sqlite}` ↔ `data/sample/manifest.json` — 3/3 size·sha256 일치, `format_version=1`
- [PASS] 팩 스모크(코어가 실제 산출물을 읽음) — area: data-pipeline — `cargo run --quiet --manifest-path pipeline/smoke/Cargo.toml -- data/sample` — `smoke OK: nodes=180360 route=531m/96s steps=2 named=0 | fts '살루떼' -> 1 results`
- [PASS] zip 배포본 — area: data-pipeline — `python -c "import zipfile..."` — entries=4(graph/map/poi/manifest), 3/3 size·sha256 일치, manifest 포함
- [PASS] POI sqlite 계약 — area: data-pipeline — `python -c "import sqlite3..."` — `application_id=0x4D554B4D`, `user_version=1`, poi 5792행, FTS `name_chosung:ㅅㄹㄸ`→1건, `name:살루*`→1건
- [PASS] mbtiles 메타 — area: data-pipeline — 위 sqlite3 조회 — `format=mvt`, `minzoom=6`, `maxzoom=14`, vector_layers 6종(roads/water/landuse/buildings/boundaries/poi), tiles 833. bounds/center는 대전 샘플 범위(`127.25,36.20,127.60,36.55`)로 설계의 전국 값과 다름 — 전국 팩에서 설계값 준수 필요
- 참고: 그래프 바이너리에 도로명 존재 확인(2811개 문자열, 첫 항목 `대덕대로`). 스모크 경로 `named=0`은 해당 531m 경로 에지에 도로명이 없기 때문이며 포맷 문제 아님

### flutter-app
- [BLOCKED-ENV] F1~F7 (7개 작업) — area: flutter-app — `dart --version` (`3.4.1`) < FRB 2.13 요구 `3.9.2`; `app/`에 `pubspec.yaml`·`lib/main.dart` 없음(`lib/ffibindings`만 존재) — 설계 R10 비고 및 사용자 결정에 따라 보류. FAIL 아님. 해소: Flutter SDK 업그레이드 후 `flutter pub get && flutter analyze`

### KPI 4종
- [PASS] 메모리 — 코어 호스트 RSS — area: rust-core — `cargo test -p mukmuk-core --release --test kpi -- --nocapture` — 600회(재탐색 300+검색 300) 후 RSS 5,464,064→5,709,824 B, **+245,760 B(0.24MB)** < 코어 힙 예산 20MB. 단 합성 20x20(400노드) 그래프 + fixture 팩 기준
- [MANUAL(승인)] 메모리 — 실기기 총 RAM 150MB, 4시간 모의주행 누수 0% — `adb shell dumpsys meminfo <pkg>` (4시간 주행 전후 비교)
- [PASS] 재탐색 — 호스트 — area: rust-core — 위 KPI 하네스 — 평균 **25.4µs**(300회, 최댓값 미기록) < 1s. 스냅+CH 쿼리+디코드 구간만 측정(직렬화·push·워커 핸드오프 제외), 합성 그래프 기준
- [MANUAL(승인)] 재탐색 — 실기기/전국 규모 — 실기기에서 이탈→재탐색 체감 시간 측정(전국 팩 필요)
- [MANUAL(승인)] 프레임 — 드랍 1% 미만(60fps) — `flutter run --profile` + DevTools Performance. 앱 미구현(F1~F7 보류)으로 정적 확인도 불가
- [PASS] 검색 — 호스트 — area: rust-core — 위 KPI 하네스 — 평균 **782.5µs**(300회, fixture 팩, 반경 10km) < 0.5s
- [MANUAL(승인)] 검색 — 전국 50km 규모 — 전국 팩에서 반경 50km 검색 시간 측정(샘플 5,792 POI는 전국 규모 아님)

### 종합
- FAIL: 0건. rust-core(P1 12/12)·data-pipeline(P1 6/6)는 실행 결과로 통과.
- KPI는 호스트·합성/픽스처 규모에서만 측정됨. 실기기 4종·전국 규모 수치는 `MANUAL`이며, **2026-11-04 사용자 승인**으로 `MANUAL(승인)` 처리했다. 앱 재개 후 실측값으로 대체한다.
- flutter-app F1~F7은 SDK 미달로 `BLOCKED-ENV`(사용자 결정). 구현 결함으로 인한 FAIL은 아님.
- 단계 상태: 검증 승인 2026-11-04. 배포 준비(4단계)는 사용자 결정으로 **보류**(Flutter SDK 업그레이드·앱 재개 후).

## 회차 2 (2026-11-04)

- 기준: `main` HEAD `40a47e8`(워킹트리 clean, `main`이 `origin/main`보다 16커밋 앞섬·미push). 미병합 브랜치 없음.
- 환경: Flutter 3.47.9 / Dart SDK `^3.13.7`(pubspec) / rustc 1.96.1 / Windows 10
- 샘플 규모: 대전 샘플 팩(그래프 180,360 노드, POI 5,792행). 전국 규모 성능은 보장하지 않는다.
- 회차 1 대비 변경: flutter-app `BLOCKED-ENV` 해소(SDK 업그레이드). 회차 1의 data-pipeline zip·POI 계약·mbtiles 메타 검사는 이번 범위가 아니어서 재실행하지 않았다(manifest 해시가 현재 파일과 일치함을 재확인).

### rust-core
- [PASS] 포맷 검사 — area: rust-core — `cd core && cargo fmt --check` — exit 0
- [PASS] 정적 분석 — area: rust-core — `cd core && cargo clippy --workspace --all-targets -- -D warnings` — exit 0, 경고 0
- [PASS] 전체 테스트 — area: rust-core — `cd core && cargo test --workspace` — 41 passed / 0 failed (mukmuk-core unit 34, bridge unit 2, bridge ffi_contract 1, graph-compiler 2, kpi 1, zero_copy 1)
- [PASS] KPI 재탐색 — 호스트 — area: rust-core — `cargo test -p mukmuk-core --release --test kpi -- --nocapture` — 평균 **25.98µs**(300회) < 1s. 회차 1(25.4µs)과 같은 범위
- [PASS] KPI 검색 — 호스트 — area: rust-core — 위 명령 — 평균 **1.00ms**(300회, 반경 10km, fixture 팩) < 0.5s. 회차 1(0.78ms)보다 느려졌으나 목표의 1/400 수준으로 여유 있음. 샘플 규모만 해당
- [PASS] KPI 메모리 — 호스트 RSS — area: rust-core — 위 명령 — 600회 후 RSS 5,156,864→5,398,528 B, **+241,664 B(0.24MB)** < 20MB 코어 예산. 합성 400노드 그래프 기준
- [PASS] FFI 계약 대조 — area: rust-core — `docs/agent/design.md` 2.2절 ↔ `core/bridge/src/api/mod.rs` ↔ `app/lib/ffibindings/api.dart` — 5개 함수 이름·인자·반환 타입 일치(`initEngine(packDir)`, `searchPoi(query,center,radiusKm,limit)`, `planRoute(start,end,profile)`, `subscribeNavigation()`, `updatePosition(pos,speedMps,headingDeg,tMs)`; `tMs`는 u64↔BigInt). `ffi_contract_flow ... ok`

### data-pipeline
- [PASS] 팩 스모크(코어가 실제 산출물을 읽음) — area: data-pipeline — `cargo run --quiet --manifest-path pipeline/smoke/Cargo.toml -- data/sample` — `smoke OK: nodes=180360 route=531m/96s steps=2 named=0 | fts '살루떼' -> 1 results`, exit 0
- [PASS] manifest 무결성 — area: data-pipeline — `stat`·`sha256sum` ↔ `data/sample/manifest.json` — 3/3 size·sha256 일치 (`map/korea.mbtiles` 15,388,672 B / `graph/korea.graph.bin` 13,654,560 B / `poi/korea.poi.sqlite` 831,488 B)

### flutter-app
- [PASS] 정적 분석 — area: flutter-app — `cd app && flutter analyze` — `No issues found!` (exit 0)
- [PASS] 테스트 — area: flutter-app — `cd app && flutter test` — **29개 전부 통과**, `All tests passed!` (exit 0). 회차 1 `BLOCKED-ENV`(F1~F7) 해소
- [PASS] FFI 경계 — area: flutter-app — `grep` — 생성물 직접 호출은 `app/lib/main.dart`의 `RustLib.init()`뿐. 그 외 `ffibindings` import는 `engine/navi_engine.dart`(래퍼)와 타입 import만 사용
- [MANUAL(승인)] F1 에뮬레이터 `init_engine`→`EngineInfo` 표시 — area: flutter-app — 직전 기록(tasks.md F1 비고, 2026-11-04 에뮬레이터 API 37) 인용, 이번 회차 재실행 안 함. 재실행: `flutter run --dart-define=MUKMUK_PACK_DIR=/data/user/0/kr.mukmuk.mukmuk_app/files/pack`
- [MANUAL(승인)] F2 실 지도 렌더·pan/zoom — 실기기(Android 라이선스 미동의 기록). `mbtiles://` 절대경로 로딩 MapLibre Android 미검증
- [MANUAL(승인)] F3 실 `search_poi` 호출·반경 필터 — 실기기
- [MANUAL(승인)] F4 경로 선 렌더·실 `plan_route` — 실기기
- [MANUAL(승인)] F5 실 주행 체감·위치 갱신 — 실기기
- [MANUAL(승인)] F6 실 R11 워커 `Rerouted` 이벤트 — 실기기
- [MANUAL(승인)] F7 실 TTS 발화·오프라인 음성 미설치 동작 — 실기기
- [MANUAL(승인)] F9 위치 서비스 토글 시 안내 문구 — 실기기
- [MANUAL(승인)] F10 스타일 경고 0건·줌별 폭 — 직전 에뮬레이터 로그·스크린샷 기록(tasks.md F10 비고) 인용, 이번 회차 재실행 안 함. 재실행: `flutter run` 후 `adb logcat | grep "Invalid geometry"` 0건 확인(z12·z10·z8)

### KPI 4종 (2026-11-04 사용자 승인 MANUAL)
- [MANUAL(승인)] 메모리 — 실기기 총 RAM 150MB, 4시간 모의주행 누수 0% — `adb shell dumpsys meminfo <pkg>` (4시간 주행 전후 비교)
- [MANUAL(승인)] 재탐색 — 실기기/전국 규모 체감 시간 — 전국 팩 필요
- [MANUAL(승인)] 프레임 — 드랍 1% 미만(60fps) — `flutter run --profile` + DevTools Performance
- [MANUAL(승인)] 검색 — 전국 50km 규모 — 전국 팩에서 반경 50km 검색 시간 측정

### git 상태
- [PASS] 워킹트리 clean, 검증 대상 커밋 전부 `main`에 포함(F9·F10 `4ba541f`·`3e4564b`, 표준 `3791c08`, 병합 `40a47e8`). 미병합 브랜치 없음

### 종합
- FAIL: 0건. area별 실패 없음.
- PASS 13건 / MANUAL 9건(실기기·에뮬레이터 재실행 필요, 이 중 F1·F10 2건은 직전 기록 인용) / MANUAL(승인) 4건 / BLOCKED-ENV 0건.
- 통과로 쓰지 않은 항목: KPI 실기기 4종과 전국 규모 수치 전부. 샘플·호스트 수치만 PASS.
- 단계 상태 갱신은 사용자(팀 리드) 몫. 이 회차는 커밋하지 않았다.

## 회차 3 (2026-11-05)

- 기준: `main` `6ca792c`(F12 경유지 병합 후). 워킹트리 clean, 미병합 브랜치 0건. 검증 대상 F12 커밋 범위 `ea122f6^..6ca792c`(F12a~g + 설계 보완).
- 환경: macOS 25.6.0 (arm64) / cargo(rustc 1.96.1 계열) / Flutter 3.47.9 stable. 회차 1·2는 Windows, 이번 회차는 macOS에서 실행.
- 샘플 규모: 픽스처 그래프(합성 400노드)·픽스처 POI. `data/` 디렉터리 없음(팩 원본 gitignore). 전국·샘플 팩 실측은 하지 않았다.
- 코드 수정 없음, 커밋 없음.

### 경계 (core·FFI 무변경)
- [PASS] core/ 무변경 — area: rust-core — `git diff --name-only ea122f6^ HEAD -- core/` 및 `c4eee81..HEAD` — 출력 0건
- [PASS] FFI 바인딩 무변경 — area: flutter-app — `git diff --name-only ea122f6^ HEAD -- app/lib/ffibindings/` — 출력 0건. FFI 시그니처가 바뀌지 않아 회차 2의 FFI 계약 대조 결과가 그대로 유효
- [PASS] 옛 진입점 제거 — area: flutter-app — `grep startRoute lib test` — 0건. 호출부는 `home_screen.dart`의 `startTrip`·`planTrip` 한 곳

### rust-core
- [PASS] 포맷 검사 — area: rust-core — `cd core && cargo fmt --check` — exit 0
- [PASS] 정적 분석 — area: rust-core — `cd core && cargo clippy --workspace --all-targets -- -D warnings` — exit 0, 경고 0
- [PASS] 전체 테스트 — area: rust-core — `cd core && cargo test --workspace` — exit 0, 44 passed / 0 failed (mukmuk-core unit 37, bridge unit 2, ffi_contract 1, graph-compiler 2, kpi 1, zero_copy 1)
- [PASS] KPI 재탐색 — 호스트 — area: rust-core — `cargo test -p mukmuk-core --release --test kpi -- --nocapture` — 평균 **13.99µs**(300회) < 1s. 합성 그래프 기준
- [PASS] KPI 검색 — 호스트 — area: rust-core — 위 명령 — 평균 **94.4µs**(300회, 반경 10km, 픽스처 팩) < 0.5s. 샘플 규모만 해당
- [PASS] KPI 메모리 — 호스트 RSS — area: rust-core — 위 명령 — RSS 4,521,984 → 5,357,568 B, **+835,584 B(0.80MB)** < 20MB 코어 예산. 회차 2(Windows) +0.24MB와 차이는 플랫폼·할당기 차이로 본다. 합성 400노드 기준

### flutter-app
- [PASS] 정적 분석 — area: flutter-app — `cd app && flutter analyze` — `No issues found!` (exit 0)
- [PASS] 테스트 — area: flutter-app — `cd app && flutter test` — **92건 전부 통과**, `All tests passed!` (exit 0). `skip`·`only` 없음
- [PASS] 가짜 완료 점검 — area: flutter-app — `grep` (`test.skip`, `skip:`, `.only(`, `TODO`, `FIXME`, `UnimplementedError`, `todo!`) 변경 파일 대상 — 0건. `.only(`는 `EdgeInsets.only` 1건뿐이라 테스트 아님

#### F12 완료조건 대비 테스트 근거 (design 7.9 시나리오)
- [PASS] (a) 중간 Arrived → 다음 구간 계획·`activeLeg` 증가·`arrived` false — area: flutter-app — `test/nav/navigation_controller_test.dart` '중간 Arrived는 다음 구간을 계획하고 도착 상태를 켜지 않는다' — 단언: activeLeg 1, arrived false, planCalls 시작=경유지·끝=목적지
- [PASS] (b) 마지막 Arrived → `arrived` true — 같은 파일 '마지막 구간의 Arrived는 도착 상태를 켠다' — 단언: arrived true, planCalls 1건(추가 계획 없음)
- [PASS] (c) 판정 B(지나침) — 같은 파일 '이탈 상태에서 경유지 60m 이내면…' (넘어감) 및 '…60m를 넘게 떨어져 있으면 넘어가지 않는다' (안 넘어감)
- [PASS] (d) Depart 발화 억제 — 같은 파일 '새 구간의 첫 출발 안내는 발화하지 않고 카드에만 반영한다' — 단언: spoken 개수 유지, 다음 Instruction만 발화
- [PASS] (e) 오래된 Rerouted 무시·활성 구간만 교체 — 같은 파일 '끝점이 활성 구간 끝에서 30m를 넘게 어긋난 재탐색은 버린다', '재탐색은 활성 구간만 바꾸고 남은 구간과 이어 보여준다'
- [PASS] (f) 전환 실패 시 재시도 후 notice — 같은 파일 '다음 구간 계획이 실패하면 경유지 기준으로 한 번 더…', '재시도도 실패하면 안내 문구를 남기고…' — 단언: 호출 2회, notice 문구, 이후 도착 신호에 재계획 없음
- [PASS] 구간 결합·겹침 제거·거리 — area: flutter-app — `test/nav/trip_test.dart` 17건 — combineLegs(이음점 1m 이내 제거·1m 초과 유지, 거리·시간 합, 구간 1개), dedupeStops(20m 이내 제거·순서 유지), haversineM, tripStops
- [PASS] planTrip 호출 순서·실패 인덱스 — area: flutter-app — `trip_test.dart` '목적지 쪽부터 역순으로…', '실패한 구간 번호를 담아 던지고…' (legIndex 1, 앞 구간 미계획), 경유지 0개·겹침·목적지 겹침 분기
- [PASS] 경유지 발화 문구 — area: flutter-app — `test/tts/instruction_text_test.dart` 2건 — 경유지 다음 `다음 경유지로`, 목적지 다음 `목적지로`
- [PASS] F12a~d 입력 상태·UI — area: flutter-app — `app_services_test.dart` 3건(끝 추가·최대 3곳 거절·삭제 후 재추가·지도 좌표 동기), `place_sheet_test.dart` '경유지로 추가' → addWaypoint, `search_screen_test.dart` '결과의 경유지 아이콘' → asWaypoint SearchPick
- [PASS] F12g 요약 문구 — area: flutter-app — `test/format_test.dart` '주행 요약은 남은 경유지가 있을 때만 경유 문구를 앞에 붙인다'. 남은 경유지 좌표 감소·목적지 제외 — `navigation_controller_test.dart` '남은 경유지 좌표는 도착할 때마다 하나씩 줄고…'. 홈·주행의 `NaviMap.waypoints` 연결은 정적 확인(`home_screen.dart:36,147`, `navigation_screen.dart:36,225`)
- 참고(실패 아님): 7.5의 `_switching` 중 Rerouted 버림 분기는 전용 테스트가 없고, 거리 기준(30m) 테스트만 있다. 필요하면 후속 테스트로 추가

### MANUAL (이번 회차에서 실행하지 않음)
- [MANUAL] F12g 에뮬레이터 모의 주행(경유지 1곳): 경유지 도착 발화·다음 구간 안내·U턴 재탐색 없음, 지도 경유지 마커 실렌더 — 사유: 이 회차는 macOS에서 에뮬레이터 모의 주행을 돌리지 않았고 팩 `data/`가 없다. 재현: `cd app && flutter run --dart-define=MUKMUK_PACK_DIR=/data/user/0/kr.mukmuk.navi/files/pack` 후 홈에서 경유지 1곳 추가 → 경로 계획 → 모의 주행, `adb logcat | grep -i "Invalid geometry\|경유"`와 스크린샷 기록
- [MANUAL] Android 빌드·설치 — 사유: 이 회차 범위 밖(macOS 환경에서 APK 빌드·NDK·Android Rust 타깃 미확인). 재현: `cd app && flutter build apk --debug --dart-define=MUKMUK_PACK_DIR=/data/user/0/kr.mukmuk.navi/files/pack`
- [MANUAL] 실 GPS 주행의 경유지 도착·구간 전환 체감 — 사유: 실기기 필요
- [MANUAL(승인)] 전국 팩 KPI(재탐색 실기기·전국, 검색 50km 전국, 메모리 4시간 누수, 프레임 드랍 1%) — 사유: 전국 팩 없음(`data/` 부재). 측정 명령은 회차 2의 KPI 4종 항목과 동일. 이번 회차 F12 변경은 코어 무변경이라 수치 영향 없음(design 7.7)

### 종합
- FAIL 0건. area별 실패 없음.
- PASS 23건 (경계 3, rust-core 6, flutter-app 14). MANUAL 4건(F12g 모의 주행, Android 빌드, 실 GPS, 전국 KPI). MANUAL(승인) 기존 항목은 재실행하지 않았다. BLOCKED-ENV 0건.
- F12 완료조건(design 7.9 a~f)은 전부 테스트 근거가 있다. F12g의 실기기 확인은 MANUAL로 남긴다.
- 단계 상태 갱신과 커밋은 하지 않았다.
