# 인수인계 — 묵묵(MukMuk) 개발 재개 가이드 (agent용)

- 작성: 2026-11-05. 최종 갱신: 2026-11-05(F13 완료 반영). 기준 커밋: `main` = `e1ca10c`.
- 이 문서는 **다른 PC/환경에서 개발을 이어갈 AI 에이전트**를 위한 것이다. 사람용 요약은 `docs/human/handoff.md`.
- 기억(메모리) 파일은 PC별 경로(`C:\Users\...\.claude\projects\...\memory\`)에 있어 옮겨지지 않는다. 이 문서가 그 내용을 대신한다.
- 작업 전 필독 순서: 이 문서 → `CLAUDE.md` → `docs/agent/standards.md` → `docs/agent/tasks.md` → `docs/agent/design.md`.

---

## 1. 현재 상태 (한눈에)

| 항목 | 상태 |
| --- | --- |
| `main` | `e1ca10c`. 앱·코어·파이프라인 P1 대부분 완료. 지도 탭 장소 식별·출발지·전국 검색(F11), 지도 이름 라벨·글꼴 팩(F13) 포함 |
| `feat/map-labels` | `main`에 병합 완료(`e1ca10c`). 더 이상 진행하지 않는다 |
| F13 지도 라벨 | **완료**. 도로명·POI 이름 라벨(z14+), 글꼴 PBF 256개(18MB, Noto Sans KR OFL). 등록 스크립트 `pipeline/glyph/register_glyphs.py`(커밋 `9184d35`). 에뮬레이터에서 한글 라벨 확인(스크린샷: scratchpad `labels_z15_tempbuild.png`). 글꼴 생성물은 `data/work/glyph_out/NotoSansKR-Regular/`(gitignore) |
| 전국 팩 백업 | `data/work/backup_national_pack/pack.tar`(975MB, 원본 manifest 포함) |
| 줌 설정 | `app/lib/config.dart`의 `kMapInitialZoom = 12`. 라벨 확인용 임시 15는 되돌렸고, `main`에는 12가 있다 |
| 미추적 파일 | `pipeline/glyph/`(빈 폴더로 보임). 커밋 전 확인 |
| 수정 중인 파일(커밋 금지) | `pipeline/graph/osm_to_graph_tsv.py`, `pipeline/manifest.py`, `pipeline/osm_extract.sh` — **줄바꿈(CRLF)만 다른 차이**. 내용 변경 아님. 스테이징하지 않는다 |

### 작업 목록 요약 (docs/agent/tasks.md 기준)
- rust-core: 12/12 완료
- flutter-app: F1~F7, F9~F11, F13 완료. **F8(팩 업데이트 UI)은 P2 — 실제로는 구현·검증됨(첫 실행 다운로드, 48f525f)**. F12(경유지)는 P2 미착수. (진행 요약 수치는 오래됨: 다음 작업에서 다시 센다)
- data-pipeline: D1~D6 완료. D7(CI 정기 빌드)·D8(전국 빌드 문서)은 P2 미착수

---

## 2. 다음에 할 일 (우선순위 순)

1. **[필수] 다음 전국 빌드 전에 `pipeline/manifest.py`에 글꼴 등록 반영.** 현재 `manifest.py`는 글꼴 항목을 등록하지 않아서, 다음 빌드 때 글꼴 PBF가 manifest에서 빠진다. `pipeline/glyph/register_glyphs.py`를 빌드 단계에 연결하거나 `manifest.py`가 같은 결과를 내도록 바꾼다. 이 파일은 CRLF 차이가 있어 줄바꿈을 먼저 정리한다(§6-7).
2. **tasks.md 진행 요약 수치 갱신**: "flutter-app 9/10" 줄이 F11·F13 완료 전 수치다. 실제 개수로 다시 센다.
3. **F13 실기기 확인 항목**: 라벨 줌 기준(z14+)과 밀집 지역 과밀 여부를 실기기에서 확인한다.
3. **P2 후보**: F12 경유지(구간별 `plan_route` 체인, 코어 변경 없이 가능), D7 CI, D8 문서.
4. **보류된 사용자 결정** (§8 참고): 실기기 MANUAL 확인, GitHub 임시 릴리스 정리, R2 토큰 삭제 확인 등.

---

## 3. 환경 준비 (새 PC에서 한 번)

### 3.1 도구 버전 (이 PC 기준)
- **Flutter 3.47.9** (Dart ≥ 3.9.2 필요, FRB 2.13 요구). 설치 경로 예: `C:\Users\<user>\flutter`.
- **Rust**: 기본 도구체인 `stable-x86_64-pc-windows-msvc`. 추가로 `stable-x86_64-pc-windows-gnu`도 설치해 두었다(`build_pbf_glyphs` 빌드용).
- **FRB codegen**: `flutter_rust_bridge_codegen` 2.13.0 (cargo로 설치).
- **Android**: Android SDK, NDK r30(`C:\Program Files\android-ndk-r30`), 에뮬레이터 `sdk_gphone64_x86_64` API 37. Gradle은 프로젝트 래퍼 사용.
- **Python 3** (파이프라인, sqlite3 표준 모듈).
- **WSL2**: 전국 데이터 빌드용. `%UserProfile%\.wslconfig`에 `memory=16GB`, `swap=0`. osmium·tippecanoe 등은 WSL에 설치.
- **CMake**(`C:\Program Files\CMake`), **MinGW gcc**(`C:\mingw64\bin`): Rust 빌드 스크립트 일부가 사용.
- **Ninja**: `pip install ninja`로 설치됨(`Scripts\ninja.exe`). Git Bash PATH에는 자동으로 들어가지 않으니 필요할 때 PATH에 추가.
- **MSYS2**: `C:\msys64`, `mingw-w64-x86_64-zlib` 설치. `fontnik` 빌드에 필요했으나 **현재 글꼴 생성은 `build_pbf_glyphs`를 쓰므로 필수는 아님**.

### 3.2 저장소와 브랜치
```
git clone <원격> mukmuk-navi
git checkout main
git checkout -b feat/<새 작업>      # 새 작업은 main에서 분기
```
- 원격 push는 사용자가 명시적으로 요청할 때만 한다(standards §5).
- 브랜치 이름 규칙: `feat/`, `fix/`, `docs/`, `chore/`, `refactor/`. 병합은 `--no-ff`.

### 3.3 커밋 규칙 (반드시 준수)
- 제목 형식: `<type>(<scope>): <한국어 설명>` (예: `feat(app): 지도 탭으로 장소 식별`).
- **공동작성자(Co-Authored-By) 문구를 넣지 않는다.** 프로젝트 규칙이 전역 설정보다 우선한다.
- 작업 단위로 쪼갠다(한 커밋 = 한 목적). 무관한 정리는 섞지 않는다.
- 게이트 통과 후 커밋. 게이트는 §5.

---

## 4. 데이터·비밀 (저장소 밖)

| 항목 | 위치 | 새 PC에서 |
| --- | --- | --- |
| 샘플 팩(대전) | `data/sample/` (gitignore), `data/sample.zip` | 재생성(`pipeline/build_all`) 또는 R2 샘플 경로에서 내려받기 |
| 전국 팩 | `data/full/`, `data/full.zip` (gitignore) | **R2에서 받기**: `https://pub-b41149f0f441435e93b044e49cd215f2.r2.dev/2026.11-full/` (공개) |
| 원본 OSM·작업물 | `data/raw/`, `data/work/` (gitignore) | 재생성. 글꼴 원본은 `data/work/glyph/NotoSansKR-Regular.otf`(Noto Sans KR, SIL OFL)를 Google Fonts에서 다시 받을 수 있다 |
| 서명 키 | `D:\android-keys\upload-keystore.jks` (저장소 밖) | **안전한 경로로 직접 옮긴다**. `app/android/key.properties`는 gitignore 대상이며 경로만 담는다. 채팅·저장소에 올리지 않는다 |
| R2 자격 증명 | AWS CLI 프로필 `r2`(로컬 설정) | 새 PC에서 **새 토큰을 발급해 `aws configure --profile r2`로 등록**. 계정 ID는 `c94e133b937018acd4bc26330d00c6b6`, 버킷은 `mukmuk-packs` |

**보안 규칙**
- 토큰·키를 채팅에 붙여넣지 않는다. 이전 세션에서 R2 키가 채팅에 노출된 적이 있다(삭제 확인은 §8).
- `key.properties`, `*.jks`, `.env`는 커밋하지 않는다(`.gitignore` 등록됨).

---

## 5. 빌드·검증 명령

**Windows Git Bash에서 `/data/...` 경로를 넘기는 명령은 반드시 `MSYS_NO_PATHCONV=1`을 먼저 설정한다**(표준 §2.7). 설정하지 않으면 `C:/Program Files/Git/data/...`로 바뀌어 `PackNotFound`가 난다(실제로 겪음).

### 5.1 게이트 (커밋 전)
```
cd core && cargo fmt --check && cargo clippy --workspace --all-targets -- -D warnings && cargo test --workspace
cd app  && flutter analyze            # 이슈 0건
cd app  && flutter test               # 전부 통과 (현재 56개)
```
- 코어를 바꿨으면 FRB 재생성: `flutter_rust_bridge_codegen generate --config-file core/bridge/flutter_rust_bridge.yaml` (**저장소 루트에서 실행**). 생성물 `app/lib/ffibindings/`는 직접 수정하지 않는다.

### 5.2 디버그 APK (에뮬레이터용)
```
export MSYS_NO_PATHCONV=1
cd app && flutter build apk --debug --dart-define=MUKMUK_PACK_DIR=/data/user/0/kr.mukmuk.navi/files/pack
adb install -r build/app/outputs/flutter-apk/app-debug.apk
adb shell monkey -p kr.mukmuk.navi -c android.intent.category.LAUNCHER 1
```
- 앱 ID: `kr.mukmuk.navi`. 이전 ID `kr.mukmuk.mukmuk_app`과 데이터 폴더가 다르다.
- 팩 배치: 앱은 `files/pack`에서 읽는다. `adb push`는 `/data/local/tmp`로 한 뒤 `run-as kr.mukmuk.navi sh -c 'cp -r ...'`로 복사한다(디버그 빌드만 `run-as` 가능).
- **복사 전 대상 기존 파일을 백업한다.** 샘플 팩을 복사하면서 전국 팩을 덮어쓴 사고가 있었다.
- 현재 에뮬레이터 `files/pack`에는 **전국 팩(2026.11)** 이 들어 있다.

### 5.3 글꼴 PBF 생성
```
export PATH="/c/mingw64/bin:$PATH"
"/c/Users/apexLee/.cargo/bin/build_pbf_glyphs.exe" <글꼴 폴더> <출력 폴더>
```
- 도구: `cargo +stable-x86_64-pc-windows-gnu install build_pbf_glyphs@1.4.1` (GNU 도구체인 필요. MSVC 도구체인에서는 `freetype-sys` 빌드가 실패).
- 입력 글꼴 폴더: `data/work/glyph/` (NotoSansKR-Regular.otf). 출력: `data/work/glyph_out/`, 스택 이름 `NotoSansKR-Regular` 하위에 `{range}.pbf`.

### 5.4 실기기 MANUAL 목록
- 지도 렌더·pan/zoom, 검색 반경 필터, 경로 선 렌더, 위치 토글, TTS 발화 — 실기기 확인 필요
- F11: 지도 탭 시트 동작 확인됨(에뮬레이터, 스크린샷). "여기로 가기"·"출발지로 설정"·출발지 칩·전국 검색은 **아직 미확인**
- 전국 반경(1000km) 검색의 0.5초 KPI — 전국 팩에서 측정 필요(샘플은 대전만 있음)
- Seoul 등 밀집 지역의 z13 표시 — `--drop-densest-as-needed`로 POI가 일부 빠짐. 허용 여부 결정 필요

---

## 6. 재개 시 주의사항 (실제로 겪은 함정)

1. **npm·cargo 설치는 프로젝트 폴더에서 실행하지 않는다.** `app/`에서 `npm install`을 하면 `app/node_modules`가 생긴다. 임시 폴더(scratchpad)에서 실행한다.
2. **네이티브 빌드 도구 체인 문제**: `fontnik`(npm)은 Ninja·ZLIB·Boost·pkg-config가 필요해 중단됐다. 현재 방식(`build_pbf_glyphs`)을 쓴다.
3. **자동 권한 검사**: 새 프로그램 설치(npm 전역, cargo install 등)는 자동 검사에서 거부될 수 있다. 거부되면 우회하지 말고, 사용자가 `! <명령>`으로 직접 실행하도록 안내한다.
4. **에이전트 위임 규칙**: 설계·구현은 하네스 에이전트(`navi-rust-dev`, `navi-flutter-dev`, `navi-data-dev` 등)에 맡긴다. 메인 세션은 조율·검증·보고만 한다(CLAUDE.md). 이번 세션에서 메인이 직접 구현해 지적받은 적이 있다.
5. **지도 탭 마커 색(`#e65100`)이 POI 점 색과 같다.** 구분이 어렵다는 피드백이 있었음. 미수정.
6. **팩 경로 문제 진단**: `PackNotFound`가 나면 먼저 `dart-define` 경로가 `C:/Program Files/Git/...`로 바뀌었는지 확인(APK의 `assets/flutter_assets/kernel_blob.bin`에서 `strings`로 확인 가능).
7. **pipeline 3개 파일의 CRLF 차이**는 커밋하지 않는다. 정리하려면 별도 `chore` 브랜치에서 줄바꿈만 LF로 통일.
8. **ODbL**: 팩을 공개 배포하므로 파생 데이터베이스 공개 의무(ODbL 4.4·4.6)와 출처 표기가 적용된다. 앱의 "© OpenStreetMap 기여자 · ODbL" 표기와 출처 화면을 유지한다. 법률 판단은 `docs/human/odbl-review.md` 참고, 최종 확인은 법률 자문.

---

## 7. 주요 문서 위치

| 문서 | 내용 |
| --- | --- |
| `CLAUDE.md` | 하네스 규칙, 개발 표준 링크, 변경 이력 |
| `docs/PRD.md` | 요구사항 원본(수정 금지) |
| `docs/agent/design.md` | 아키텍처, FFI 계약(2.2절), 팩 포맷(3절). FFI 시그니처는 임의로 바꾸지 않는다 |
| `docs/agent/tasks.md` | 작업 목록(F·R·D), 완료 조건, 진행 요약 |
| `docs/agent/standards.md` | 코드·테스트·브랜치·커밋 규칙(번호 규칙) |
| `docs/agent/verify.md` | QA 기록(회차 1·2, MANUAL 승인 기록) |
| `docs/agent/release.md` | 배포 체크리스트, R2 공개 경로 |
| `docs/agent/odbl-review.md` | ODbL 조항 인용 |
| `.claude/skills/mukmuk-orchestrator/` | 파이프라인 조율 스킬 |

---

## 8. 열린 결정 (사용자 확인 필요)

- [ ] 실기기 MANUAL 확인 결과(§5.4) 공유
- [ ] GitHub 임시 릴리스 `pack-sample-2026.11`: 예전 zip(NOTICE 없음). 삭제할지 갱신할지 결정
- [ ] 이전 세션에서 채팅에 노출된 R2 Access Key 삭제·교체 확인
- [ ] 18080 포트에 떠 있던 `python http.server`(PID 45208) 종료 확인
- [ ] 릴리스 APK에 `android.permission.DUMP`가 들어간 원인 조사(출시 전)
- [ ] `docs/agent/release.md`·`docs/human/release.md` 권한 항목 갱신(INTERNET 재선언 반영)
- [ ] 전국 검색 반경 1000km(전국)의 KPI 측정 승인
- [ ] 밀집 지역 POI 누락(drop-densest) 허용 여부
- [ ] 법률 자문 의뢰 여부(ODbL, 벡터 타일 분류)

---

## 9. 재개 체크리스트 (새 세션 첫 10분)

1. `git status`, `git branch --show-current`로 브랜치 확인. 미커밋 변경(특히 `pipeline/` 3개 파일의 CRLF 차이)을 먼저 파악한다.
2. `docs/agent/tasks.md`의 F13 항목(완료)과 §2의 다음 작업(manifest.py 글꼴 등록)을 확인한다.
3. `flutter --version`(3.47.9), `rustup toolchain list`(msvc·gnu), `adb devices`로 환경을 확인한다.
4. `data/work/glyph_out/NotoSansKR-Regular/`에 PBF 256개가 있는지 확인한다.
5. 에뮬레이터 `files/pack`이 전국 팩인지 샘플인지 확인한 뒤 작업한다(§5.2).
6. 작업 전에 이 문서와 `CLAUDE.md`의 변경 이력을 최신으로 맞춘다.
