# 묵묵 개발 표준 (사람용 요약)

상세 규칙: [docs/agent/standards.md](../agent/standards.md) · 작업 상태: [docs/agent/tasks.md](../agent/tasks.md)

## 기본 원칙
- 경계는 설계대로 고정한다. FFI 함수와 데이터 팩 포맷은 설계 문서가 정본이다.
- 완료는 명령 결과나 실측 근거가 있을 때만 `[x]`로 표시한다. 실기기 확인이 필요하면 `MANUAL`로 남긴다.
- 가짜 완료(건너뛴 테스트, 빈 스텁)는 완료로 세지 않는다.

## 게이트 (커밋 전 모두 통과)
- Rust: `cargo fmt --check`, `cargo clippy --workspace --all-targets -- -D warnings`, `cargo test --workspace`
- Flutter: `flutter analyze` 이슈 0건, `flutter test` 전부 통과
- 데이터: `pipeline/build_all` 스모크 통과

## 브랜치
- `main`은 항상 게이트를 통과한 상태로 둔다.
- 작업은 `feat/`, `fix/`, `docs/`, `chore/` 브랜치에서 하고, 끝나면 `--no-ff`로 `main`에 병합한다.
- push는 요청할 때만 한다.

## 커밋
- 제목 형식: `<type>(<scope>): <한국어 제목>` (type은 영문 소문자)
- 공동작성자나 도구 서명 문구는 넣지 않는다.
- 한 커밋은 한 논리 단위다. 파일은 경로로 지정해서 스테이징한다.
- 본문에는 무엇을, 왜 바꿨는지와 검증 결과, `MANUAL` 항목을 적는다.

## 금지
- 키·서명 파일·대용량 데이터(팩, mbtiles, sqlite, graph.bin, osm.pbf)를 저장소에 넣지 않는다.
- 생성된 FFI 바인딩(`app/lib/ffibindings/`)을 손으로 고치지 않는다.
- 외부 입력(OSM/XML, 사용자 입력)을 검증 없이 처리하지 않는다.

## 문서
- 표준은 `docs/agent/standards.md`(상세)와 이 파일(요약) 2트랙이다.
- 표준을 바꾸면 두 문서를 함께 고치고 프로젝트 `CLAUDE.md`의 변경 이력에 남긴다.
