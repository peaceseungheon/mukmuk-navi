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
