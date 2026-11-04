# 묵묵(MukMuk) — 오프라인 내비게이션

요구사항 원본: `docs/PRD.md` (수정 금지)

## 하네스: 묵묵 앱 개발 파이프라인

**목표:** 설계(opus) → 구현(sonnet/haiku) → 검증(haiku) → 배포 준비(haiku)를 단계 승인 게이트로 진행하고 산출물을 `docs/agent/`(AI용)·`docs/human/`(사람용 요약)에만 관리한다.

**호출 조건:** 묵묵 앱의 설계·구현·검증·배포 준비, 단계 재실행, 검증 실패 수정, 진행 확인을 요청받으면 `mukmuk-orchestrator` 스킬을 사용한다. 단순 질문에는 직접 답해도 된다.

**개발 표준:** 코드·테스트·브랜치·커밋 규칙은 [docs/agent/standards.md](docs/agent/standards.md)(요약: [docs/human/standards.md](docs/human/standards.md))를 따른다. 커밋에는 공동작성자 문구를 넣지 않는다.

**변경 이력:**
| 날짜 | 변경 내용 | 대상 | 사유 |
| --- | --- | --- | --- |
| 2026-11-03 | Harness v2로 처음 구성 (에이전트 6, 스킬 1) | 전체 | - |
| 2026-11-03 | `datapack-build` 스킬 추가, 오케스트레이터에 데이터 팩 갱신 분기 추가 | skills, navi-architect, navi-data-dev, artifact-spec | 정기 데이터 팩 빌드 운영 절차 누락. 에이전트 추가 대신 스크립트+CI 방식 |
| 2026-11-03 | 단계 상태(승인 기록) 절, MANUAL(승인)/BLOCKED-ENV 게이트, 병렬화 근거, 데이터 팩 CI 입력·보관 규칙 보완 | orchestrator, artifact-spec, navi-release, datapack-build | 코드 리뷰 지적(MEDIUM 5건) 반영 |
| 2026-11-03 | tasks.md 형식 강화(최소 단위, 완료조건·우선순위 필드, `[~]` 상태, 진행 요약, PRD 추적 표) | artifact-spec, navi-architect, orchestrator, rust/flutter/data-dev | 문서만 보고 AI가 진행 상황을 파악하도록 요구 |
| 2026-11-04 | 개발 표준 문서 신설(`docs/agent/standards.md`, `docs/human/standards.md`), 기능 브랜치 병합 규칙, 공동작성자 문구 금지 | standards(신규), CLAUDE.md, artifact-spec | 코드·커밋 기준 문서 부재. 사용자 결정(2트랙, feature→main --no-ff, 커밋 제목 한국어·문구 없음) 반영 |
