---
name: datapack-build
description: 묵묵 데이터 팩(mbtiles, 라우팅 그래프 바이너리, POI sqlite)을 전국 단위로 빌드·검증·패키징하는 절차. 데이터 팩 갱신, OSM 최신본 반영, 정기 빌드 스크립트·CI 스케줄 작성, 팩 빌드 실패 원인 분석을 요청하면 사용한다. 앱 코드 구현이나 샘플 지역 개발용 팩에는 쓰지 않는다.
---

# datapack-build

정기 실행은 에이전트가 아니라 **스크립트 + CI 스케줄**이 한다. 같은 입력이면 같은 결과가 나와야 하고, 에이전트를 매번 부르면 토큰만 든다. 에이전트는 스크립트를 만들 때와 실패를 분석할 때만 쓴다.

## 빌드 스크립트 (`pipeline/build_all`) 요구사항
순서: ① OSM 추출 다운로드(+ 국토지리정보원 데이터는 수동 제공 경로 사용) → ② 그래프 컴파일 → ③ mbtiles 생성 → ④ POI sqlite(FTS5) 생성 → ⑤ **스모크 검증** → ⑥ 압축 → ⑦ `manifest.json` 작성.
- 포맷은 `docs/agent/design.md`의 데이터 팩 명세와 일치해야 한다. 앱이 그대로 읽는 파일이기 때문이다.
- ⑤ 스모크 검증: Rust 코어의 검증 바이너리/테스트로 그래프를 mmap으로 열고, 샘플 경로 1건과 FTS5 쿼리 1건이 성공해야 한다. 실패하면 ⑥ 이후를 실행하지 않는다.
- `manifest.json`: 팩 버전, 원본 OSM 날짜, 파일별 크기·sha256, 빌드 일시, 설계 문서의 포맷 버전. 앱 업데이트(P2)가 이 파일로 새 팩을 판별한다.
- 이전 팩 대비 크기가 ±30% 넘게 변하면 경고를 출력한다(원본 데이터 오류 조기 발견용).
- 대용량 산출물은 git에 올리지 않는다. CDN 업로드는 스크립트에 넣지 않고 사용자가 한다(`docs/agent/release.md`의 `USER` 항목).

## CI 스케줄
`.github/workflows/datapack.yml`에 월 1회 cron + 수동 실행(workflow_dispatch)을 둔다. 실패하면 로그를 아티팩트로 남기기만 한다. 사용자가 실패를 알리면 `navi-data-dev`가 로그를 읽고 원인을 고치고, `navi-qa`가 스모크를 재확인한다.

## 갱신 요청 처리 (오케스트레이터가 사용)
1. `pipeline/build_all`이 있는지 확인한다. 없으면 `navi-data-dev`로 먼저 만든다.
2. 사용자가 팩을 직접 빌드했거나 CI 로그를 주면 `navi-qa`가 스모크 결과를 `docs/agent/verify.md`에 회차로 추가한다.
3. `docs/agent/release.md`의 「데이터 팩」 절에 팩 버전·sha256·`USER`(CDN 업로드)를 갱신한다.
