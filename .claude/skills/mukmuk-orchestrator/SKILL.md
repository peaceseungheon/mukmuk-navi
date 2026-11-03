---
name: mukmuk-orchestrator
description: 묵묵(MukMuk) 오프라인 내비게이션 앱의 설계→구현→검증→배포 준비 파이프라인을 조율한다. 묵묵 앱의 설계, 구현, 검증, 배포 준비, 특정 단계 시작·재실행, 검증 실패 수정, 설계 변경, 진행 상황 확인을 요청하면 반드시 사용한다. "다시 실행", "재실행", "수정", "보완", "이전 결과 기반으로", "구현만 다시", "검증만 다시", "데이터 팩 갱신" 같은 후속 요청에도 사용한다. 단순 질문에는 쓰지 않는다.
---

# mukmuk-orchestrator

**실행 모드:** 서브에이전트 위임 + 단계 승인 게이트. 에이전트끼리 대화할 필요가 없고 단계 사이에 사용자 승인이 들어가므로, 단계마다 `Agent`를 호출하고 산출물 파일로 인수인계한다.

## 파이프라인

| 단계 | 에이전트 (모델) | 입력 | 출력 |
| --- | --- | --- | --- |
| 1 설계 | `navi-architect` (opus) | `docs/PRD.md` | `docs/agent/design.md`, `docs/agent/tasks.md`, `docs/human/design.md` |
| 2 구현 | `navi-rust-dev` (sonnet), `navi-flutter-dev` (haiku), `navi-data-dev` (haiku) | design.md, tasks.md | `core/`, `app/`, `pipeline/`, tasks.md 갱신 |
| 3 검증 | `navi-qa` (haiku) | 위 전부 | `docs/agent/verify.md`, `docs/human/verify.md` |
| 4 배포 준비 | `navi-release` (haiku) | verify.md, design.md | `docs/agent/release.md`, `docs/human/release.md` |

산출물 형식과 경로 규칙은 `references/artifact-spec.md`, KPI 측정법은 `references/kpi-checks.md`를 읽는다.

## 0단계: 상태 확인
시작 시 `docs/agent/tasks.md`(맨 위 `## 단계 상태` 절 포함)와 `docs/agent/verify.md`의 존재·상태를 읽고 요청을 분류한다. 사용자 승인을 받을 때마다 `단계 상태`에 `설계: 승인 YYYY-MM-DD`처럼 기록한다. 세션이 바뀌어도 승인 여부를 알 수 있는 곳이 여기뿐이다.
- 산출물이 없다 → 1단계부터.
- 특정 단계만 요청("구현만 다시", "검증만") → 해당 단계만. 앞 단계 산출물이 없으면 알리고 중단한다.
- 설계 변경 요청 → 1단계를 피드백 부분만 수정하도록 재호출. 이후 2단계는 영향받는 작업만 `tasks.md`에서 `[ ]`로 되돌리고, 3·4단계는 `단계 상태`의 승인을 무효화해 다시 실행한다.
- 검증 실패 수정 → 2단계를 실패 `area` 에이전트에게만 재호출 후 3단계 재실행.
- 데이터 팩 갱신·빌드 스크립트·CI 실패 분석 → `datapack-build` 스킬을 따른다(`navi-data-dev` + `navi-qa`, 결과 기록은 `navi-release`). 정기 실행 자체는 CI가 하므로 에이전트를 상시 호출하지 않는다.

## 단계 실행 규칙
1. **설계:** `navi-architect`를 호출한다. 끝나면 `docs/human/design.md`와 「미결 사항」을 사용자에게 보여주고 **승인을 받는다**(AskUserQuestion). 승인 전에는 구현으로 넘어가지 않는다. 설계 오류가 구현까지 번지는 비용이 가장 크기 때문이다.
2. **구현:** `tasks.md`의 의존 순서에 따라 에이전트를 호출한다. 서로 의존하지 않는 에이전트는 한 메시지에서 병렬 호출한다(`data-pipeline`↔`rust-core`는 데이터 팩 포맷이, `rust-core`↔`flutter-app`은 FFI 계약이 설계에 고정돼 있으면 병렬 가능). `BLOCKED` 보고가 있으면 사용자에게 알리고 설계 수정 여부를 묻는다. 구현 에이전트가 계약을 임의로 바꾸지 않게 하는 것이 이 규칙의 목적이다.
3. **검증:** `navi-qa`를 호출한다. 결과가 전부 PASS이거나 `MANUAL(승인)`이고 `BLOCKED-ENV`가 없으면 사용자 승인 후 4단계로 간다. `MANUAL`은 사용자에게 보여주고 승인받아 `verify.md`에서 `MANUAL(승인)`으로 바꾼다. FAIL이 있으면 `area`별로 구현 에이전트를 재호출한 뒤 재검증한다. **수정→재검증은 최대 2회**까지 반복한다. 2회 수정 후에도 FAIL이면 중단하고 사용자에게 보고한다(무한 루프는 토큰만 쓴다).
4. **배포 준비:** `navi-release`를 호출한다. 스토어 제출·CDN 업로드·서명은 하지 않고 `USER` 할 일 목록만 보고한다.

각 단계 후 사용자에게 3줄 이내로 보고하고 `docs/agent/tasks.md` 상태를 갱신한다.

## 데이터 전달
산출물 파일로만 전달한다(`docs/agent/*`). 에이전트 프롬프트에는 파일 경로와 해당 단계의 역할만 넘기고 내용을 복붙하지 않는다. 컨텍스트가 줄어 토큰이 절약된다.

## 오류 처리
- 에이전트가 실패하면 한 번 재호출한다. 또 실패하면 부분 산출물을 직접 확인해 어디까지 됐는지 `tasks.md`에 기록하고 사용자에게 보고한다.
- 사용량 한도·권한 거부처럼 재시도해도 같은 결과인 실패는 재시도하지 않고 바로 보고한다.
- 빌드 도구 미설치(`BLOCKED-ENV`)는 설치 항목을 알리고 해당 단계를 보류한다.
- 에이전트가 하지 않은 판단(제외한 이유 등)을 오케스트레이터가 추측해서 채우지 않는다.

## 테스트 시나리오
- **정상:** "묵묵 설계 시작" → architect 호출 → human/design.md 확인·승인 → 구현 3개 호출 → QA PASS → 사용자 승인 → release 호출, USER 할 일 보고.
- **오류:** QA가 `area: rust-core` FAIL 1건 보고 → rust-dev만 재호출 → QA 재실행 → 여전히 FAIL이면 같은 방식으로 한 번 더 수정·재검증하고, 2회 수정 후에도 FAIL이면 중단하고 사용자에게 로그 요약 보고.
- **후속:** "검증만 다시" → `verify.md` 존재 확인 → navi-qa만 호출, 회차 번호 누적.
