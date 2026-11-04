# 묵묵(MukMuk) 개발 표준 — agent용 상세

- 상태: 확정 (2026-11-04). 변경은 이 문서와 `docs/human/standards.md`를 함께 갱신한다.
- 적용 범위: `core/`(Rust), `app/`(Flutter/Dart), `pipeline/`(데이터 구축), 저장소 전체(git·문서)
- 설계 원본: `docs/agent/design.md` (FFI 계약·데이터 팩 포맷은 여기 표준보다 우선)

이 문서는 AI 에이전트와 사람이 같은 기준으로 판단하도록 **규칙을 번호로 고정**한다. 각 규칙은 검증 방법을 함께 적는다.

---

## 0. 공통 원칙

- **C-1 경계 고정:** FFI 시그니처(design 2절)와 데이터 팩 포맷(design 3절)은 구현 에이전트가 임의로 바꾸지 않는다. 바꿔야 하면 `BLOCKED`로 보고하고 설계를 수정한다.
- **C-2 작은 변경:** 한 작업 ID(tasks.md의 R·F·D 번호)는 한 목적의 변경으로 끝낸다. 무관한 정리는 같은 커밋에 넣지 않는다.
- **C-3 증거 기반 완료:** 완료 표시(`[x]`)는 완료조건의 명령 결과 또는 기록된 실측 근거가 있을 때만 한다. 실기기로만 확인되는 항목은 `MANUAL`로 남긴다.
- **C-4 가짜 완료 금지:** `test.skip`, 빈 테스트, `TODO` 스텁, `unimplemented!()`/`UnimplementedError`로 통과시키지 않는다. 필요하면 `BLOCKED: 사유`로 적는다.
- **C-5 비밀·대용량 금지:** 키·서명 파일·`.env`·팩 원본(zip, mbtiles, sqlite, graph.bin, osm.pbf)은 저장소에 넣지 않는다. 필요한 경로는 `--dart-define`이나 스크립트 인자로 주입한다.
- **C-6 경계 검증:** 외부 입력(사용자 입력, OSM/XML, 네트워크 응답, 파일 내용)은 처리 전에 검증한다. 실패는 명시적 오류로 올리고 조용히 삼키지 않는다.

---

## 1. Rust 코어 (`core/`)

### 1.1 구성
- 워크스페이스: `core/Cargo.toml`. 멤버는 `core/core`(mukmuk-core, 순수 로직), `core/bridge`(mukmuk-bridge, FFI 어댑터), `core/graph-compiler`(bin).
- edition 2021. 공통 버전은 `[workspace.package]`/`[workspace.dependencies]`에 둔다.
- FFI 브리지(`core/bridge`)만 flutter_rust_bridge에 의존한다. `mukmuk-core`는 FFI 타입을 알지 못해야 한다.

### 1.2 게이트 (커밋 전 필수, 전부 통과)
```
cd core
cargo fmt --check
cargo clippy --workspace --all-targets -- -D warnings
cargo test --workspace
```
- 경고는 `-D warnings`로 오류 취급한다. `#[allow(...)]`는 이유를 주석으로 남길 때만 허용한다.
- KPI 측정(재탐색·검색·RSS): `cargo test -p mukmuk-core --release --test kpi -- --nocapture`. 결과 수치는 `verify.md`에 기록한다.

### 1.3 오류·패닉
- 공개 함수는 `Result<_, EngineError>`(FFI) 또는 크레이트 고유 에러 타입을 반환한다.
- `.unwrap()`·`.expect()`·`panic!`은 **테스트 코드에서만** 쓴다. 불변식이 확실한 곳은 주석으로 근거를 남긴다.
- FFI 경계에서 에러 메시지를 사용자에게 보여줄 때는 Dart 쪽 `engine_error_text`처럼 매핑한다. 내부 경로·스택은 노출하지 않는다.

### 1.4 구조와 크기
- 모듈은 design 1절 구조를 따른다: `pack/`, `routing/`, `matching/`, `search/`, `tbt/`.
- 함수는 50줄 이하, 파일은 800줄 이하를 목표로 한다(넘으면 분리 계획을 `verify.md` 또는 커밋 본문에 적는다).
- 할당 최소화: 쿼리 경로에서 그래프 전체를 힙에 복사하지 않는다(design 4절 메모리 예산). zero-copy 접근 테스트(`zero_copy.rs`)를 유지한다.

### 1.5 테스트
- 단위 테스트: 같은 파일 하단 `#[cfg(test)] mod tests`. 통합 테스트: 크레이트의 `tests/`.
- 샘플 데이터는 `fixtures.rs`나 테스트 안에서 생성한다. 저장소에 바이너리 픽스처를 추가하지 않는다.
- 외부 알고리즘(CH 등)은 독립 구현(`fast_paths`)과 교차검증한다(R3 방식).

---

## 2. Flutter 앱 (`app/`)

### 2.1 구성
- 디렉터리: `lib/main.dart`(진입), `lib/app*.dart`(조립), `engine/`(Rust 호출 래퍼), `map/`, `search/`, `nav/`, `tts/`, `ffibindings/`(생성물).
- 화면 로직과 엔진 호출을 분리한다. 화면 위젯은 `NaviEngine` 같은 래퍼를 통해서만 FFI를 부른다.

### 2.2 게이트
```
cd app
flutter analyze            # 이슈 0건
flutter test               # 전부 통과
```
- 린트: `analysis_options.yaml`의 `flutter_lints`를 따른다. 규칙을 끄려면 파일 단위 `// ignore_for_file`에 이유를 적는다.
- `android/**`와 `rust_builder/**`는 분석 대상이 아니다(설정 파일에 명시).

### 2.3 생성물
- `lib/ffibindings/`는 **직접 수정하지 않는다.** 재생성은 FRB codegen(`core/bridge/flutter_rust_bridge.yaml`)으로 한다.
- 생성물 변경은 같은 커밋에 `core/bridge`의 원인 변경과 함께 넣는다.

### 2.4 UI 스레드와 성능 (design 4절)
- 무거운 연산은 Dart에 두지 않는다. 라우팅·매칭·검색은 FRB async 호출로 Rust 워커에서 실행한다.
- 위치 갱신은 10Hz 이하로 쓰로틀하고, 갱신되는 위젯만 다시 빌드한다(부모 `setState` 금지, 스냅 위치는 소스 갱신).

### 2.5 설정 주입
- 팩 경로 등 환경 값은 `const String.fromEnvironment`로 받는다. 빌드 명령에 `--dart-define=MUKMUK_PACK_DIR=<경로>`를 붙인다.
- 기기 내 경로는 앱 내부 저장소(`/data/user/0/<applicationId>/files/...`)를 쓴다. 외부 저장소는 앱이 읽지 못하는 경우가 있다.

### 2.6 테스트
- 테스트 경로는 `lib/`를 미러링한다(`lib/nav/x.dart` ↔ `test/nav/x_test.dart`).
- 외부 스트림·플러그인은 가짜 구현으로 대체해 예외 경로(위치 꺼짐, 권한 거부)를 검증한다.
- 실기기 전용 확인(지도 렌더, 위치 토글, 실제 음성)은 `MANUAL`로 기록하고 통과로 세지 않는다.

### 2.7 에뮬레이터 실행 주의 (Windows Git Bash)
- `adb`나 `flutter run`에 `/data/...` 경로를 넘길 때는 `MSYS_NO_PATHCONV=1`을 먼저 설정한다. 설정하지 않으면 경로가 Windows 경로로 바뀐다.

---

## 3. 데이터 파이프라인 (`pipeline/`)

- 도구: 셸 글루와 Python 3 표준 라이브러리(sqlite3). 새 외부 의존성은 design 5절에 먼저 등록한다.
- 재현성: 스크립트는 입력 경로와 버전을 인자로 받고, 산출물 manifest에 sha256과 크기를 기록한다.
- 엔트리포인트는 `pipeline/build_all` 하나다. 개별 스크립트를 호출만 하고 로직을 복제하지 않는다.
- 외부 OSM/XML은 신뢰하지 않는다. DTD·엔티티 선언이 있는 입력은 거부한다(`osm_to_graph_tsv.py`의 `_reject_entity_declarations`).
- 산출물 검증: `build_all`의 스모크(경로 1건 + FTS 1건)와 크기 ±30% 경고를 통과해야 팩을 인정한다.
- 데이터 원본과 산출물은 `data/`(gitignore)에만 둔다.

---

## 4. 테스트 공통

- 신규 로직은 테스트를 먼저 쓰거나(RED→GREEN), 최소한 같은 커밋에 넣는다.
- 커버리지 목표는 80%다. **현재 커버리지는 측정하지 않았다.** 측정 도구 도입은 별도 작업으로 추적한다.
- 버그 수정은 재현 테스트를 같이 넣는다.

---

## 5. 브랜치 전략

- `main`은 **항상 게이트를 통과한 상태**로 유지한다.
- 작업은 기능 브랜치에서 한다: `feat/<범위>`, `fix/<범위>`, `docs/<범위>`, `chore/<범위>`, `refactor/<범위>`.
  - 예: `feat/app-map-search`, `fix/build-cargokit`, `docs/standards`
- 완료되면 `main`에 `--no-ff`로 병합한다. 병합 커밋 제목은 `Merge branch '<이름>'`을 쓴다.
- 브랜치 이름과 병합은 로컬 작업이다. **push는 사용자가 명시적으로 요청할 때만** 한다.
- 2026-11-04 이전 커밋 14개는 `main`에 직접 쌓였다. 이 이력은 그대로 두고, 이후 작업부터 이 규칙을 적용한다.

---

## 6. 커밋 규칙

### 6.1 제목
```
<type>(<scope>): <한국어 제목>
```
- `type`은 영문 소문자: `feat`, `fix`, `refactor`, `docs`, `test`, `chore`, `perf`, `ci`.
- `scope`는 영역 이름: `core`, `bridge`, `pipeline`, `app`, `build`, `docs`, `standards`, `harness`. 여러 영역이면 가장 주된 영역 하나를 쓴다.
- 제목은 50자 안팎, 마침표 없음, 명령형 또는 명사형으로 쓴다.
- 작업 ID가 있으면 제목 또는 본문에 적는다(예: `R3`, `F9·F10`).

### 6.2 본문
- 무엇을, 왜 바꿨는지 쓴다. 구현 세부는 코드가 설명하므로 생략한다.
- 검증 결과를 한 줄로 남긴다(예: `cargo test 41개 통과`, `flutter analyze 이슈 0건`).
- 알려진 한계나 `MANUAL` 항목은 본문에 적는다.

### 6.3 금지 사항
- **공동작성자·도구 서명 문구(Co-Authored-By, Generated with 등)를 넣지 않는다.** (2026-11-04 사용자 결정)
- `--no-verify`로 훅을 건너뛰지 않는다. 훅이 실패하면 원인을 고친다.

### 6.4 단위와 순서
- 한 커밋은 한 논리 단위다. 기능 하나, 수정 하나, 문서 하나.
- 같은 파일에 기능과 무관한 포맷 변경이 섞이면 분리한다.
- 커밋 전에 `git status`로 의도하지 않은 파일이 없는지 확인한다. 특히 `build/`, `target/`, 대용량 파일, IDE 설정. 잠금 파일(`app/pubspec.lock`, `core/Cargo.lock`, `pipeline/smoke/Cargo.lock`, cargokit의 `pubspec.lock`)은 추적 대상이므로 의존성을 바꾼 커밋에 함께 넣는다.
- 파일은 경로로 명시해서 스테이징한다(`git add <path>`). `git add -A`는 쓰지 않는다.
- 커밋마다 빌드가 되는 것을 원칙으로 한다. 여러 커밋을 묶어 검증한 경우 본문에 그 사실을 적는다.

### 6.5 커밋 예시
```
feat(app): MapLibre 지도 렌더와 목적지 검색 (F2·F3)

- map: mbtiles 벡터 소스 기반 지도, pan/zoom
- search: 검색어 → search_poi → 거리순 결과

검증: flutter analyze 이슈 0건, flutter test 29개 통과.
MANUAL: 실기기 지도 렌더 확인.
```

---

## 7. 문서 규칙

- 산출물 위치와 형식은 `.claude/skills/mukmuk-orchestrator/references/artifact-spec.md`가 정본이다.
- 표준 문서는 `docs/agent/standards.md`(이 문서)와 `docs/human/standards.md`(요약, 40줄 이내) 2트랙이다.
- 설계 원본 `docs/PRD.md`는 수정하지 않는다.
- 작업 상태의 정본은 `docs/agent/tasks.md`다. 진행 요약 줄은 오케스트레이터가 갱신한다.
- 표준을 바꾸면 변경 이력을 남긴다(프로젝트 `CLAUDE.md`의 변경 이력 표).

---

## 8. 보안 체크 (커밋 전)

- 비밀값(키, 토큰, 서명 파일)이 없는지 확인한다.
- 사용자 입력은 빈 값, 과도한 길이, 잘못된 형식을 검사한다.
- 외부 데이터 파서는 엔티티 확장·경로 탐색을 막는다.
- 오류 메시지에 내부 경로·스택 트레이스를 노출하지 않는다.

---

## 9. 변경 절차 요약

1. tasks.md에서 작업 ID와 완료조건을 확인한다.
2. 기능 브랜치를 만든다(§5).
3. 구현 → 게이트 실행(§1.2, §2.2) → 결과 기록.
4. 경로 기준으로 스테이징하고 커밋한다(§6).
5. 완료조건을 충족하면 tasks.md를 `[x]`로 바꾸고 커밋한다.
6. `main`에 `--no-ff` 병합한다. push는 요청 시에만.
