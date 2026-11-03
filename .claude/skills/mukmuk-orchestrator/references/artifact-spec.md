# 산출물 규칙

1인 개발이라 산출물은 아래 외에는 만들지 않는다. 중간 보고서·회의록·별도 로그 파일을 추가하지 않는다.

## 구조
```
docs/
  PRD.md              # 원본 요구사항 (수정 금지)
  agent/              # AI가 읽는 문서: 상세, 구조화, 사실 위주
    design.md         # 아키텍처 + FFI 계약 + 데이터 팩 포맷 + 모듈 구조 + 미결 사항
    tasks.md          # 작업 체크리스트 (유일한 진행 상태 원본)
    verify.md         # 검증 결과 (회차 누적)
    release.md        # 배포 체크리스트
  human/              # 사람이 읽는 문서: 요약, 각 20~40줄 이내
    design.md, verify.md, release.md
```
`human/`은 같은 단계의 에이전트가 `agent/` 문서를 마친 뒤 **요약만** 쓴다. 사람이 판단·승인하는 데 필요한 것(결정, 위험, 할 일)만 담고 상세 근거는 `agent/` 링크로 대신한다.

## agent/design.md 필수 절
1. 모듈 구조(디렉터리: `core/`, `app/`, `pipeline/`, `data/sample/`)
2. FFI 계약: 함수명, 입력/출력 타입, 에러 타입, 스레드·비동기 규칙
3. 데이터 팩 포맷: mbtiles 메타, 그래프 바이너리 레이아웃, sqlite 스키마(FTS5)
4. KPI별 모듈 예산(RAM, 지연)
5. 기술 선택(이름·버전·이유 1줄)
6. 미결 사항

## agent/tasks.md 형식
```
## 단계 상태
설계: 미승인 | 구현: 진행 전 | 검증: 진행 전 | 배포 준비: 진행 전
(승인 시 `설계: 승인 2026-11-03`처럼 오케스트레이터가 갱신)
## rust-core
- [ ] R1 그래프 mmap 로더 (의존: 없음)
- [ ] R2 ... (의존: R1)  BLOCKED: 사유
## flutter-app
## data-pipeline
```
ID는 `R`/`F`/`D` + 번호. 완료한 에이전트가 `[x]`로 바꾼다.

## agent/verify.md 형식
회차마다 `## 회차 N (날짜)` 절을 추가한다. 항목은 `- [PASS|FAIL|MANUAL|MANUAL(승인)|BLOCKED-ENV] 항목명 — area: rust-core|flutter-app|data-pipeline — 재현 명령 — 핵심 로그`.

## human/verify.md 형식
KPI 4종 표(목표 / 측정값 / 판정)와 판정 한 줄. 측정하지 못한 값은 `미측정(MANUAL)`로 쓴다.

## agent/release.md 형식
항목 태그: `AUTO-OK`(확인 완료), `AUTO-FAIL`, `USER`(사용자가 해야 함). 비밀 값은 쓰지 않는다.
`## 데이터 팩` 절을 두고 최신 팩 버전, sha256, 원본 OSM 날짜, CDN 업로드(`USER`) 상태를 갱신한다. 별도 데이터 팩 문서는 만들지 않는다.
