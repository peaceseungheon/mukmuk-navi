# 기능 개발 목록 (원본: docs/PRD.md)

## 사용 규칙
- 다음 작업 = 의존 항목이 모두 [x]인 첫 [ ] / 완료조건 충족 시에만 [x] / 막히면 줄 끝에 `BLOCKED: 사유` 표기(해소 시 삭제) / 기존 ID 변경 금지(추가·분할만 가능)
- P2 항목은 P1 전체 완료 후 착수한다.
- 착수 시 `[~]`, 완료 시 `[x]`로 바꾸고 `진행 요약` 수치를 함께 갱신한다.

## 단계 상태
설계: 승인 2026-11-03 (F12 설계 보완 승인 2026-11-05) | 구현: P1 전체 완료(F12·D7·D8은 P2 미착수) | 검증: 승인 2026-11-04 (회차 2, MANUAL 9건 승인) | 배포 준비: 진행 중 2026-11-04

## 진행 요약
rust-core 12/12 | flutter-app 12/13 (F1~F11·F13 완료, F12는 P2 진행 중 — 하위 F12a~F12g 5/7, 다음 착수: F12f) | data-pipeline 6/8 (P1 D1~D6 완료, D7·D8은 P2)

## rust-core
### 데이터 팩·그래프 로딩
- [x] R1 manifest 파싱·팩 검증 (의존: 없음) [P1] — 완료조건: 샘플 manifest.json을 읽어 필수 파일 존재와 format_version=1을 검사하고 불일치 시 EngineError::FormatMismatch를 반환 (cargo test)
- [x] R2 그래프 mmap+rkyv zero-copy 접근 (의존: R1) [P1] — 완료조건: 샘플 korea.graph.bin을 mmap으로 열어 헤더·nodes·road_names·edge_road_name 배열을 힙 복사 없이 읽고, 힙 할당량이 파일 크기와 무관함을 테스트로 확인

### 라우팅
- [x] R3 CH 전처리(노드 순서·숏컷 생성) + graph-compiler bin (의존: R2) [P1] — 완료조건: 도로명 열이 있는 edges.tsv에서 CH를 생성해 road_names·edge_road_name을 포함한 korea.graph.bin으로 직렬화하고, fast_paths의 최단경로와 일치함을 교차검증 (cargo test + bin 실행)
- [x] R4 양방향 CH 쿼리 (의존: R3) [P1] — 완료조건: 샘플 그래프 A→B 경로가 단순 Dijkstra 결과와 일치, 100회 평균 쿼리 시간을 로그로 기록
- [x] R5 경로 디코딩(숏컷 언팩→polyline·steps) (의존: R4) [P1] — 완료조건: CH 경로를 원본 에지 열로 복원해 polyline·RouteStep 목록(road_name이 edge_road_name→road_names로 채워지고 없으면 빈 문자열)과 총 거리·시간을 생성 (cargo test)

### 길 안내·맵 매칭
- [x] R6 TBT 매뉴버 분류·안내 상태 머신 (의존: R5) [P1] — 완료조건: 샘플 경로에서 Depart/좌·우회전/Arrive 시퀀스가 기대와 일치 (cargo test)
- [x] R7 칼만 필터 (의존: 없음) [P1] — 완료조건: 노이즈 GPS 시뮬레이션에서 필터 후 위치 분산이 감소함을 수치로 확인 (cargo test)
- [x] R8 맵 매칭 스냅·이탈 판정 (의존: R2, R7) [P1] — 완료조건: GPS 좌표가 최근접 도로에 스냅되고 off_route 플래그가 샘플 케이스와 일치 (cargo test)

### 검색
- [x] R9 FTS5 검색·초성·거리 정렬 (의존: R1) [P1] — 완료조건: 샘플 poi.sqlite에서 초성/풀텍스트 쿼리 + 반경 필터 + 거리순 정렬 결과가 기대와 일치 (cargo test)

### FFI·워커·측정
- [x] R10 FFI 브리지(bridge crate) 생성 (의존: R4, R5, R6, R8, R9) [P1] — 완료조건: flutter_rust_bridge codegen 성공, Dart 바인딩 생성, 각 함수가 실패를 EngineError로 전달 (cargo test + codegen) — 비고: codegen 성공, app/lib/ffibindings에 Dart 생성. freezed build_runner는 설치된 Dart 3.4.1 < FRB 2.13 요구 3.9.2로 실행 불가(Flutter SDK 업그레이드 필요).
- [x] R11 재탐색 워커·NavigationEvent 스트림 (의존: R10, R8) [P1] — 완료조건: 이탈 감지 시 백그라운드 워커에서 재계산해 Rerouted 이벤트를 스트림으로 전달 (통합 테스트)
- [x] R12 KPI 측정 하네스 (의존: R4, R8, R9) [P1] — 완료조건: 재탐색·검색 시간 측정과 반복 탐색 후 RSS 증가 추이를 기록하는 명령(cargo bench/통합 테스트) 제공

## flutter-app
### 지도·검색
- [x] F1 앱 스캐폴드 + FRB 바인딩 연결 (의존: R10) [P1] — 완료조건: flutter analyze 통과, init_engine 호출로 EngineInfo 수신 — 비고(2026-11-04): 정적 항목 완료(analyze 통과, main에서 RustLib.init→initEngine 연결). Android 연동 완료·검증: `flutter build apk --debug` 성공, APK에 `libmukmuk_bridge.so`(arm64-v8a·armeabi-v7a·x86_64) 포함 확인. 빌드 수정 2건: (a) `android/gradle.properties`에 `kotlin.incremental=false`(프로젝트 D:·pub 캐시 C: 드라이브 불일치로 Kotlin 증분 캐시 오류), (b) `rust_builder/cargokit/.../artifacts_provider.dart`에서 패키지명 `-`→`_` 변환(원본은 `libmukmuk-bridge.so`를 찾아 산출물을 조용히 누락시킴). 실측 완료(2026-11-04, 에뮬레이터 sdk_gphone64_x86_64/API 37): init_engine이 EngineInfo를 반환해 홈 화면 하단에 `데이터 2026.11`(`info.packVersion`) 표시, 대전 mbtiles 지도 렌더 확인. 팩은 앱 내부 저장소 `/data/user/0/kr.mukmuk.mukmuk_app/files/pack`에 두고 `--dart-define=MUKMUK_PACK_DIR=<그 경로>`로 빌드해야 한다(외부 저장소 `/sdcard/Android/data/...`는 adb로 넣은 파일을 앱이 읽지 못해 PackNotFound). 후속 결함 2건은 아래 F9·F10으로 분리.
- [x] F2 MapLibre 지도 + mbtiles 렌더·pan/zoom (의존: D3) [P1] — 완료조건: 대전 mbtiles를 소스로 지도 렌더·pan/zoom 동작, 무거운 연산이 Dart에 없음(정적 확인) — 비고: 스타일(`lib/map/mbtiles_style.dart`)·지도 위젯(`lib/map/navi_map.dart`) 코드 완료, 무거운 연산 없음(정적 확인). 실 렌더·pan/zoom은 MANUAL(실기기, Android 라이선스 미동의). `mbtiles://` 절대경로 로딩은 MapLibre Android에서 미검증
- [x] F3 검색 UI + 결과 목록 (의존: R10, D2) [P1] — 완료조건: 검색어→search_poi 호출→거리순 결과 표시, 반경 필터 동작 — 비고: 위젯 테스트(가짜 엔진)로 검증. 실 FFI 호출·반경 필터 실측은 MANUAL(실기기)

### 출발지·목적지 지정 (2026-11-05 추가)
- [x] F11 지도 탭 장소 식별 + 출발지·목적지 지정 + 전국 검색 반경 (의존: F2, F3, R9) [P1] — 완료조건: 지도 탭 → nearby_poi로 주변 장소 조회 → 시트에서 "여기로 가기"(경로 계획)·"출발지로 설정" 동작, 탭 지점 마커 표시, 검색 반경에 "전국" 추가, 출발지 지정 시 검색·경로 기준점이 바뀜 — 비고: 코어 `nearby_poi`(core/core `nearby_poi`, 테스트 3건)·FFI 추가(설계 2.2절 갱신), 앱 단위 테스트 신규 7건(`tapped_place_test`, `place_sheet_test`, `radius_choice_test`), 전체 52건 통과, analyze 0건. 실기기 탭 반응·마커 위치·출발지 칩 동작은 MANUAL. 전국 반경(1000km) 검색의 0.5초 KPI는 전국 팩에서 MANUAL(승인) 측정 필요
- [ ] F12 경유지 입력 (의존: F12a~F12g) [P2] — 완료조건: 하위 F12a~F12g가 모두 [x]. 출발지·목적지 사이 경유지를 추가하면 구간별 plan_route를 이어 붙여 하나의 경로(polyline·안내)로 표시, 재탐색 시 경유 순서 유지 — 비고: 설계 design.md 7절(2026-11-05 보완). 코어·FFI 변경 없음, BLOCKED 없음(7.8). 코어 동작 계약은 design 2.2절. 차량(`car`)만 대상
  - [x] F12a 구간 결합 순수 함수 (의존: F11) [P2] — 완료조건: `lib/nav/trip.dart`에 `Stop`·상수 4개·`haversineM`·`dedupeStops`·`combineLegs`(design 7.1·7.2)가 있고 `test/nav/trip_test.dart`(이음점 1m 중복 제거, 거리·시간 합, 구간 1개 그대로, 20m 이내 지점 제거·순서 유지, 알려진 두 점 거리) 통과 — 비고(2026-11-05): 완료. trip_test 9건 통과, analyze 0건, flutter test 전체 통과
  - [x] F12b 경유지 문구 함수 (의존: 없음) [P2] — 완료조건: `instruction_text.dart`에 `waypointArrivalSpeech(n, nextIsDestination:)`가 design 7.6 두 문구를 정확히 반환하고 단위 테스트 2건 통과 — 비고(2026-11-05): 완료. 단위 테스트 2건 통과
  - [x] F12c 경유지 입력 UI·상태 (의존: F12a) [P2] — 완료조건: `AppServices.waypoints`(최대 3, 초과 시 스낵바), 장소 시트 "경유지로 추가"(`PlaceAction.addWaypoint`), 검색 결과 trailing 아이콘과 `SearchPick` pop 값, 홈 경유지 칩(×로 삭제)이 design 7.1대로 동작하고 시트·검색 위젯 테스트 통과 — 비고(2026-11-05): 완료. 홈 `_planTo`는 F12d에서 체인 계획으로 바꾼다(F12c 시점에는 목적지 단일 구간)
  - [x] F12d 체인 경로 계획 (의존: F12a, F12c) [P2] — 완료조건: `planTrip`이 겹친 지점을 뺀 구간을 역순으로 plan_route 호출하고 실패 시 `TripPlanException(legIndex)`를 던지며, 홈 `_planTo`가 이를 써서 `nav.startTrip`(기존 `startRoute` 삭제) 후 주행 화면으로 가고 실패 시 구간 이름 문구를 보여줌. 가짜 엔진 테스트로 호출 순서·실패 인덱스 확인, 경유지 0개 동작은 기존과 같음(기존 테스트 통과) — 비고(2026-11-05): 완료. `tripStops`(겹침 제거·목적지 하나 대체)를 함께 두고 `planTrip`은 그 결과로 계획한다. 가짜 엔진 테스트 8건(역순 호출·실패 인덱스·0개·겹침·문구) 포함 flutter test 79건 통과
  - [x] F12e 주행 중 구간 전환 (의존: F12b, F12d) [P2] — 완료조건: 컨트롤러가 중간 `Arrived`(판정 A)와 이탈+60m 이내(판정 B) 중 먼저 온 것 하나로 `_advanceLeg`를 실행(전환 중 위치 미전송, 경유지 문구 발화, 다음 구간 plan_route, 실패 시 경유지 기준 1회 재시도 후 notice·`_legFailed`), 새 구간 Depart 발화 억제, 마지막 `Arrived`만 `arrived=true`. 컨트롤러 테스트 design 7.9 (a)(b)(c)(d)(f) 통과 — 비고(2026-11-05): 완료. 판정 B 거리 60m는 활성 구간 끝 기준, 판정 A는 끝 근처 위치가 있을 때만 받음(옛 구간 늦은 신호 거름). 구간 전환 컨트롤러 테스트 8건 추가(design 7.9 a·b·c·d·f 포함), flutter test 87건 통과
  - [ ] F12f 재탐색 경유 순서 유지 (의존: F12e) [P2] — 완료조건: `Rerouted`가 활성 구간만 교체해 `combineLegs([새 경로, 남은 구간])`로 표시하고, 전환 중이거나 끝점이 활성 구간 끝과 30m 넘게 다르면 버림. 컨트롤러 테스트 design 7.9 (e) 통과
  - [ ] F12g 주행 화면 경유지 표시 (의존: F12d) [P2] — 완료조건: 하단 요약 `경유 m곳 남음 · 거리 · 시간`, `NaviMap.waypoints` 원 마커(#1565c0)가 홈·주행 화면에 연결되고 `flutter analyze` 0건·`flutter test` 전부 통과. 에뮬레이터 모의 주행(경유지 1곳)에서 경유지 도착 발화·다음 구간 안내·U턴 재탐색 없음을 로그/스크린샷으로 기록(실 GPS 주행은 MANUAL)

### 지도 라벨 (2026-11-05 추가)
- [x] F13 지도 도로명·POI 이름 라벨 + 글꼴 팩 (의존: F2, D5) [P1] — 완료조건: (a) 스타일에 도로명(roads, z14~, 선 따라)·POI 이름(poi, z14~) symbol 레이어가 있고 스타일 단위 테스트 통과, (b) 팩 `glyphs/NotoSansKR-Regular/{range}.pbf`를 스타일 `glyphs`(file://)가 가리키며 에뮬레이터에서 한글 라벨이 그려짐(스크린샷), (c) 글꼴 OFL 라이선스 문구를 출처 화면에 표기, (d) 글꼴 생성 스크립트를 pipeline/에 두고 manifest에 등록 — 비고(2026-11-05): 완료. 글꼴 PBF는 build_pbf_glyphs(cargo 설치판)로 Noto Sans KR Regular(SIL OFL 1.1, 글리프 22,862개)에서 생성, 256개 18MB(`data/work/glyph_out/`, 저장소 제외). 등록 스크립트 `pipeline/glyph/register_glyphs.py`가 PBF size·sha256을 manifest files에 `glyphs/NotoSansKR-Regular/<range>.pbf`로 추가(필수 3개 외 항목 허용을 Dart `PackManifest.parse`·Rust `Manifest::validate`에서 확인). 에뮬레이터(API 37) 확인: 전국 팩 `files/pack`의 mbtiles·graph·poi는 바꾸지 않고 glyphs 폴더와 manifest만 추가, `file://` 글꼴 로딩으로 줌 15에서 도로명(둔산로, 문정로)과 POI 이름(한국은행, 스타벅스, 대전시청) 한글 표시 확인(스크린샷 scratchpad/labels_z15_tempbuild.png). 확인 방법: 줌 15는 임시 빌드(kMapInitialZoom 15)로 보았고 커밋 코드는 12로 되돌려 재빌드함. 전국 팩 백업은 `data/work/backup_national_pack/pack.tar`(원본 manifest 포함). 미완료 후속: 팩 빌드 파이프라인 `pipeline/manifest.py`에 글꼴 등록이 없어 다음 전국 빌드에서는 글꼴이 빠짐(파일 3개는 기존 dirty 상태라 이번 커밋 제외).

### 길 안내
- [x] F4 경로 표시 + TBT 안내 UI (의존: R10, F2) [P1] — 완료조건: plan_route 호출→polyline·스텝 렌더, 매뉴버 아이콘 표시 — 비고: 매뉴버 아이콘·문구는 단위 테스트로 전 변형 확인. 경로 선 렌더와 실 plan_route는 MANUAL(실기기)
- [x] F5 위치 갱신 위젯(맵매칭 스냅 반영) (의존: R10, F2) [P1] — 완료조건: 모의 위치로 update_position 호출, 스냅 위치를 최소 범위 위젯만 갱신(코드 리뷰) — 비고: 모의 주행 소스·10Hz 쓰로틀·스냅 반영을 단위 테스트로 확인. 위치 갱신은 GeoJSON 소스만 변경(부모 setState 없음). 실 주행 체감 확인은 MANUAL
- [x] F6 재탐색 이벤트 구독·경로 교체 (의존: R11, F4) [P1] — 완료조건: Rerouted 이벤트 수신 시 경로 즉시 교체·이탈 표시 — 비고: 가짜 이벤트 스트림 단위 테스트로 교체·이탈 해제 확인. 실 R11 워커 이벤트는 MANUAL
- [x] F7 TTS 음성 안내 (의존: R11, F6) [P1] — 완료조건: Instruction 이벤트→네이티브 TTS(ko-KR 오프라인 음성) 발화, 네트워크 미사용 — 비고: 이벤트→문장 생성·발화 호출을 단위 테스트로 확인. 네트워크 음성 제외(network_required) 필터 적용. 실 발화와 오프라인 음성 미설치 시 동작(design 6절 5번)은 MANUAL. 음성 미설치면 발화를 생략하고 안내 문구만 표시. 미설치 안내 배너 추가(2026-11-04)

### 에뮬레이터 실측 후속 결함 (2026-11-04)
- [x] F9 위치 서비스 꺼짐·권한 거부 처리 (의존: F5) [P1] — 완료조건: geolocator 위치 스트림의 `LocationServiceDisabledException`·권한 거부가 unhandled exception 없이 처리되어 사용자에게 안내 문구가 표시되고 앱이 계속 동작, 해당 경로 단위 테스트 추가 — 비고: listenFixes/locationErrorText(test/nav/listen_fixes_test.dart)로 스트림 오류를 안내 문구로 전달, 홈 스낵바·주행 화면 notice 연결. 실기기 위치 서비스 토글 확인은 MANUAL
- [x] F10 도로 레이어 스타일 폭·지오메트리 경고 수정 (의존: F2) [P1] — 완료조건: 에뮬레이터 z13 이하에서도 도로가 줌에 비례한 선 두께로 구분되어 보이고(스크린샷 확인), `Invalid geometry in line layer` 경고의 원인(타일 지오메트리 또는 스타일 `line-*` 표현식)을 확인해 해소하거나 무해함을 근거와 함께 기록 — 비고: 타일 roads는 전부 LineString으로 정상이나 boundaries 등 한 레이어에 점·선·면이 혼재 → 스타일에 geometry-type 필터 추가 후 경고 0건(에뮬레이터 로그), 도로를 등급별 3레이어·지수 보간 폭으로 변경. 스크린샷은 scratchpad f10_before/after_default.png / 재검증(2026-11-04): z12 3회 연속 실행(15:37:56·15:39:16·15:40:36) 경고 0건, z10(15:41:56)·z8(15:43:16)도 0건, 스크린샷 scratchpad f10_z12_*·f10_z10_*·f10_z8_* (줌 구분 폭 확인). 초기 줌은 임시 변경 후 12로 복구

### 데이터 관리 (P2)
- [x] F8 데이터 팩 업데이트 UI (의존: F1) [P2] — 완료조건: Wi-Fi에서 manifest 비교 후 새 팩 다운로드·교체 플로우 동작 — 비고(2026-11-05): `MUKMUK_PACK_URL` 있을 때만 활성. lib/packs/(manifest 검증·경로 탈출 거부·sha256/size 대조·pack.new→pack 교체·재초기화 실패 시 롤백), 홈 하단 배너(진행률·다시 확인). analyze 0건, test 41개 통과(신규 9: test/packs/pack_updater_test.dart). 새 팩은 다음 실행부터 지도까지 반영(엔진은 재초기화, 지도 위젯은 재시작 필요).
  - 수동 확인(에뮬레이터 API 37, http.server 18080 — 8000은 호스트에서 바인드 거부): 시드 2026.11 → 서버 2026.12로 manifest+3파일 다운로드·`files/pack` 교체 성공, 재시작 후 홈에 `데이터 2026.12`·지도 렌더, 재확인 시 manifest만 요청(다운로드 없음). 미확인(MANUAL): Wi-Fi 끈 상태 안내, 실제 https 서버. 주의: kPackDir를 `files/pack`으로 두면 첫 교체 때 그 시드가 대체됨.

## data-pipeline
### 샘플 데이터
- [x] D1 OSM 샘플 추출 스크립트 (의존: 없음) [P1] — 완료조건: 대전 지역 OSM 데이터를 다운로드·추출하는 스크립트가 재현 가능하게 실행
- [x] D2 POI sqlite 생성 스크립트 (의존: D1) [P1] — 완료조건: 설계 스키마(FTS5+name_chosung)대로 대전 poi.sqlite 생성, 초성/풀텍스트 쿼리 1건 성공
- [x] D3 mbtiles 생성 스크립트 (의존: D1) [P1] — 완료조건: 설계 메타(minzoom 6/maxzoom 14/vector_layers)대로 대전 mbtiles 생성
- [x] D4 그래프 컴파일 호출 (의존: R3, D1) [P1] — 완료조건: 도로명 열을 포함한 edges.tsv로 graph-compiler를 돌려 대전 graph.bin 생성, 헤더 magic·format_version=1과 road_names 비어있지 않음을 확인
- [x] D5 샘플 팩 조립 + manifest (의존: D2, D3, D4) [P1] — 완료조건: data/sample/에 팩 디렉터리+manifest.json 생성, 앱이 그대로 읽는 경로 구조 확인

### 전국 빌드·CI (P2)
- [x] D6 build_all 통합 스크립트 + 스모크 검증 (의존: D2, D3, D4) [P1] — 완료조건: build_all 한 번에 ①추출→⑦manifest 전 단계 실행, 스모크(경로 1건+FTS 1건) 통과, 크기 ±30% 경고 동작
- [ ] D7 CI 스케줄 datapack.yml (의존: D6) [P2] — 완료조건: 월 1회 cron+workflow_dispatch, 아티팩트 보관 30일, 실패 시 로그만 보관
- [ ] D8 전국 빌드 실행 경로 문서화 (의존: D6) [P2] — 완료조건: 전국 빌드 명령과 아티팩트 한계 초과 시 self-hosted 실행 안내를 문서화

## PRD 추적

| PRD 항목 (기능·KPI) | 작업 ID |
| --- | --- |
| 오프라인 맵 디스플레이 (P1) | D3, F2 |
| 로컬 장소/주소 검색 (P1) | D2, R9, F3 |
| 초고속 오프라인 라우팅 (P1) | R3, R4, R5, F4 |
| 즉각적 재탐색 (P1) | R11, F6 |
| 고정밀 맵 매칭 (P1) | R7, R8, F5 |
| 음성 안내 TTS (P1) | R6, F7 |
| 통합 데이터 패키지 업데이트 (P2) | D6, D7, D8, F8 |
| 경유지 입력 (PRD 외, 2026-11-05 사용자 추가, P2) | F12, F12a~F12g |
| KPI: 메모리 150MB·누수 0% | R2, R12 |
| KPI: 재탐색 1초 | R11, R12, F12f(경유 경로도 활성 구간만 재탐색) |
| KPI: 프레임 드랍 1% | F2, F5, F6 (정적) + 검증 MANUAL |
| KPI: 검색 0.5초(50km) | R9, R12 |
