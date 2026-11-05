# 묵묵 (MukMuk)

인터넷 없이 동작하는 오프라인 자동차 내비게이션 앱(Android). 지도·검색·경로 탐색·길 안내가 모두 기기 안에서 실행되고, 데이터는 미리 받아 둔 **데이터 팩**을 쓴다.

- 연산(라우팅, 맵 매칭, 턴바이턴 안내, 검색)은 Rust 코어가, 화면(지도·검색 UI·음성)은 Flutter가 맡는다. 둘은 [flutter_rust_bridge](https://github.com/fzyzcjy/flutter_rust_bridge) 2.x로 연결한다.
- 경로 탐색은 Contraction Hierarchies, 그래프는 mmap + rkyv zero-copy로 읽는다.
- 요구사항 원본은 [docs/PRD.md](docs/PRD.md), 설계는 [docs/agent/design.md](docs/agent/design.md)(요약: [docs/human/design.md](docs/human/design.md)).

## 저장소 구조

| 경로 | 내용 |
| --- | --- |
| `core/` | Rust 워크스페이스. `core/core`(순수 로직), `core/bridge`(FFI 어댑터), `core/graph-compiler`(그래프 컴파일 bin) |
| `app/` | Flutter 앱. `lib/ffibindings/`는 생성물이라 직접 수정하지 않는다 |
| `pipeline/` | 데이터 팩 구축 스크립트. 엔트리포인트는 `pipeline/build_all` |
| `docs/` | `agent/`(AI용 상세), `human/`(사람용 요약), `PRD.md`(수정 금지) |
| `data/` | 팩 원본·산출물. 저장소에 포함되지 않는다(gitignore) |

## 준비물

| 도구 | 버전 | 용도 |
| --- | --- | --- |
| Flutter | 3.47.9 (Dart ≥ 3.9.2) | 앱 빌드 |
| Rust | stable | 코어 빌드·테스트. 앱 빌드 시 cargo가 자동 호출된다 |
| flutter_rust_bridge_codegen | 2.13.0 | FFI 바인딩 재생성(코어 API를 바꿀 때만) |
| Android SDK / NDK | NDK r30, 에뮬레이터 API 37 | Android 빌드·실행 |
| CMake | 최근 버전 | Rust 빌드 스크립트 |
| Python 3 | 표준 라이브러리만 사용 | 데이터 파이프라인 |
| osmium, tippecanoe 등 | - | 전국 데이터 빌드용(Linux/WSL2 권장, 메모리 16GB) |

> 개발 이력의 주 환경은 Windows(Git Bash)이다. macOS/Linux에서도 같은 명령을 쓴다. Windows에서 `/data/...` 경로를 인자로 넘길 때는 먼저 `export MSYS_NO_PATHCONV=1`을 설정한다.

## 빠른 시작: 앱을 에뮬레이터에서 실행

앱은 시작할 때 팩 디렉터리에서 지도·그래프·POI를 읽는다. 팩 경로는 빌드 시 `--dart-define`으로 주입한다.

### 1. 데이터 팩 준비 (둘 중 하나)

- **샘플 팩(대전, 약 20MB) 직접 생성**
  ```
  pipeline/build_all            # 결과: data/sample/ (manifest.json 포함), 압축본 data/sample.zip
  ```
  OSM 추출·타일·그래프 빌드가 필요하다. 옵션은 `pipeline/build_all --help`.
- **전국 팩 내려받기:** 공개 주소 `https://pub-b41149f0f441435e93b044e49cd215f2.r2.dev/2026.11-full/`에서 받는다. 앱에 `MUKMUK_PACK_URL`을 주면 첫 실행 때 앱이 직접 내려받는다(아래 3번).

### 2. 앱 빌드·설치

```
cd app
flutter pub get
flutter build apk --debug \
  --dart-define=MUKMUK_PACK_DIR=/data/user/0/kr.mukmuk.navi/files/pack
adb install -r build/app/outputs/flutter-apk/app-debug.apk
adb shell monkey -p kr.mukmuk.navi -c android.intent.category.LAUNCHER 1
```

- 앱 ID는 `kr.mukmuk.navi`. 앱은 `files/pack`에서 팩을 읽는다.
- 첫 빌드는 Rust 컴파일 때문에 오래 걸린다.

### 3. 팩을 기기에 넣기

디버그 빌드에서는 `run-as`로 앱 내부 저장소에 복사한다.

```
adb push data/sample /data/local/tmp/pack
adb shell run-as kr.mukmuk.navi sh -c 'mkdir -p files && cp -r /data/local/tmp/pack files/'
```

- **복사 전에 기기의 기존 팩을 백업한다.** 팩을 덮어써 전국 팩을 잃은 사고가 있었다.
- 또는 빌드에 `--dart-define=MUKMUK_PACK_URL=https://pub-b41149f0f441435e93b044e49cd215f2.r2.dev/2026.11-full/`를 추가하면 앱이 첫 실행 때 팩을 내려받는다.
- 에뮬레이터에서는 실제 GPS 대신 앱의 **모의 주행**으로 안내를 확인할 수 있다.

### 빌드 인자 정리

| `--dart-define` | 필수 | 설명 |
| --- | --- | --- |
| `MUKMUK_PACK_DIR` | 예 | 기기 안의 팩 디렉터리 |
| `MUKMUK_PACK_URL` | 아니오 | 팩 서버 주소. 없으면 업데이트/내려받기 기능이 숨겨진다 |

## 테스트와 품질 게이트

커밋 전에 아래가 모두 통과해야 한다([개발 표준](docs/agent/standards.md) §1.2, §2.2).

```
cd core && cargo fmt --check && cargo clippy --workspace --all-targets -- -D warnings && cargo test --workspace
cd app  && flutter analyze      # 이슈 0건
cd app  && flutter test         # 전부 통과
```

코어 KPI 측정(재탐색 시간·검색 속도·메모리):

```
cd core && cargo test -p mukmuk-core --release --test kpi -- --nocapture
```

실기기에서만 확인되는 항목(지도 렌더, 위치 토글, 실제 음성)은 `MANUAL`로 기록한다([verify.md](docs/agent/verify.md)).

## FFI 바인딩 재생성

`core/bridge`의 공개 API를 바꿨을 때만 **저장소 루트에서** 실행한다. 생성물(`app/lib/ffibindings/`)은 직접 수정하지 않는다. FFI 시그니처는 설계(design.md 2.2절)에 고정돼 있으므로 임의로 바꾸지 않는다.

```
flutter_rust_bridge_codegen generate --config-file core/bridge/flutter_rust_bridge.yaml
```

## 데이터 팩

팩은 `manifest.json`, 벡터 타일(`mbtiles`), 라우팅 그래프 바이너리, POI SQLite(FTS5), 글꼴 PBF로 이루어진다. 포맷은 [design.md 3절](docs/agent/design.md)에 고정돼 있고 정기 빌드 절차는 `datapack-build` 스킬(`.claude/skills/datapack-build/`)에 있다.

- 팩 원본과 산출물은 `data/`에만 두고 커밋하지 않는다.
- 지도 데이터는 © OpenStreetMap 기여자, ODbL 1.0이다. 파생 데이터베이스 공개 의무와 출처 표기가 적용된다([ODbL 검토](docs/human/odbl-review.md)). 앱의 출처 표기 화면을 유지한다.
- 글꼴은 Noto Sans KR(SIL OFL)이다.

## 기여 규칙

- 브랜치: `main`에서 `feat/`, `fix/`, `docs/`, `chore/`, `refactor/` 접두사로 분기하고 `--no-ff`로 병합한다. push는 요청이 있을 때만 한다.
- 커밋 제목: `<type>(<scope>): <한국어 설명>`. 공동작성자·도구 서명 문구는 넣지 않는다.
- 키·서명 파일(`*.jks`, `key.properties`), `.env`, 팩 원본은 커밋하지 않는다.
- 자세한 규칙: [docs/agent/standards.md](docs/agent/standards.md) (요약 [docs/human/standards.md](docs/human/standards.md)).

## 더 읽을 문서

| 문서 | 내용 |
| --- | --- |
| [docs/agent/handoff.md](docs/agent/handoff.md) | 현재 상태, 환경 준비, 함정, 열린 결정 (요약 [human](docs/human/handoff.md)) |
| [docs/agent/tasks.md](docs/agent/tasks.md) | 작업 목록과 진행 상황 |
| [docs/agent/verify.md](docs/agent/verify.md) | 검증 기록과 KPI |
| [docs/agent/release.md](docs/agent/release.md) | 배포 체크리스트 |
