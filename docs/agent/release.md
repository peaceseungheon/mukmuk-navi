# 배포 준비 점검 (agent)

- 기준: `docs/agent/verify.md` 회차 2 (검증 승인 2026-11-04, FAIL 0건, BLOCKED-ENV 0건), `docs/agent/design.md`, `docs/agent/standards.md`
- 점검일: 2026-11-04 (2차 점검) / 환경: Windows 10 / Flutter 3.47.9 / Dart SDK `^3.13.7` / build-tools 36.1.0
- 직전 점검(1차) 대비 변경: applicationId·앱 이름·아이콘·서명 설정이 바뀌어 1차의 AUTO-FAIL 3건이 해소됐다. 새로 확인된 사항은 릴리스 병합 매니페스트의 네트워크 권한(항목 6)이다.
- 범위: 점검만 수행. 스토어 제출·서명 파일 생성·CDN 업로드·비밀 값 기록은 하지 않았다. 코드·`tasks.md`는 수정하지 않았고 커밋하지 않았다. 키스토어 경로와 비밀번호는 기록하지 않았다.
- 태그: `AUTO-OK`(에이전트가 확인 완료) / `AUTO-FAIL`(확인했더니 배포 기준 미달) / `USER`(사용자가 결정·수행해야 함) / `MANUAL`(실기기 확인 필요)

## 요약

| 태그 | 건수 |
| --- | --- |
| AUTO-OK | 16 |
| AUTO-FAIL | 1 |
| USER | 7 |
| MANUAL | 1 |

판정: **배포 후보 빌드는 준비됨(서명된 release APK 생성 확인). 배포 자체는 미완료.** 남은 것은 권한 결정, 법적·표기 확인, 전국 팩과 CDN, 초안 릴리스 공개 결정, 실기기 확인이다.

## 점검 항목

### 1. applicationId · namespace
- [AUTO-OK] `applicationId = "kr.mukmuk.navi"`, `namespace = "kr.mukmuk.navi"` (`app/android/app/build.gradle.kts:16,36`). 커밋 `20d72b0`에서 변경.
- 참고: 같은 파일 35행에 `TODO: Specify your own unique Application ID` 주석이 남아 있다. ID는 이미 설정됐으므로 주석 삭제가 필요하다(코드 변경이라 이번 점검에서는 하지 않았다).

### 2. 버전
- [AUTO-OK] `app/pubspec.yaml:19` `version: 1.0.0+1`. Flutter가 `versionName=1.0.0`, `versionCode=1`로 전달한다(`build.gradle.kts`의 `flutter.versionCode`·`flutter.versionName`).
- [USER] 릴리스 번호 정책 결정(메이저.마이너.패치 규칙, `versionCode` 증가 방식, 1.0.0+1 유지 여부).

### 3. 앱 이름 · 아이콘
- [AUTO-OK] 표시 이름 `android:label="묵묵"` (`app/android/app/src/main/AndroidManifest.xml:6`).
- [AUTO-OK] 런처 아이콘 5개 밀도 크기 확인(PNG IHDR): mdpi 48, hdpi 72, xhdpi 96, xxhdpi 144, xxxhdpi 192 px. 기본 Flutter 아이콘이 아님은 커밋 `3759838`(5개 파일 교체)으로 확인.
- 참고: 1024px 원본은 저장소에 없다(사용자 보관, 커밋 메시지 기재).

### 4. 서명
- [AUTO-OK] 서명 설정 연결: `signingConfigs.create("release")`가 `key.properties`에서 값을 읽고(`build.gradle.kts:9-13,20-26`), `buildTypes.release`가 이 설정을 쓴다(`:50-52`). `key.properties`는 `app/android/.gitignore:12`와 루트 `.gitignore:33`에 의해 제외되며 git 추적 대상이 아니다. 키스토어(`*.jks`, `*.keystore`)도 제외 규칙이 있다.
- [AUTO-OK] APK 서명 인증서 일치: `app/build/app/outputs/flutter-apk/app-release.apk`(2026-11-04 17:53)의 서명자 SHA-256 `9B:3A:1C:0F:77:36:E8:0C:B7:25:41:14:BC:88:57:D7:CC:00:4F:6C:CB:E5:FF:1E:A1:2B:8E:2B:09:47:42:3D`가 업로드 키스토어 키 항목의 SHA-256과 같다(`apksigner verify --print-certs`, `keytool -list -v`). debug 키(`CN=Android Debug`)로 서명된 것이 아니다.
- 비밀번호·키스토어 경로는 기록하지 않는다.

### 5. 권한
- [AUTO-OK] 메인 매니페스트(`app/android/app/src/main/AndroidManifest.xml:3-4`): `ACCESS_FINE_LOCATION`, `ACCESS_COARSE_LOCATION` 2개뿐.
- debug·profile 매니페스트에만 `INTERNET`이 있다(Flutter 기본, hot reload용).
- 항목 6 참고: 릴리스 병합 매니페스트에는 플러그인이 추가한 권한이 들어 있다. 이 항목은 "INTERNET 없음"이 아니다.

### 6. 릴리스 병합 매니페스트 권한 (확인 결과 불일치)
- [AUTO-FAIL] 릴리스 병합 매니페스트(`app/build/app/intermediates/merged_manifest/release/processReleaseMainManifest/AndroidManifest.xml:35-37`)에 `android.permission.INTERNET`, `ACCESS_NETWORK_STATE`, `ACCESS_WIFI_STATE`가 있다. 동적 리시버 권한 `kr.mukmuk.navi.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION`도 있다. 출처는 플러그인(`maplibre_gl`, `geolocator`, `flutter_tts` 등)으로 추정한다. 메인 매니페스트에는 없다.
- 오프라인 앱 기준으로 세 권한이 필요 없다면 `tools:node="remove"`로 제거하는 방식을 검토한다. 제거 후에는 실기기에서 네트워크 호출이 실패해도 앱이 동작하는지 확인해야 한다(`MANUAL`, 아래 항목 9).
- [USER] 세 권한 유지·제거 결정.

### 7. minSdk · targetSdk
- [AUTO-OK] `minSdk = flutter.minSdkVersion`, `targetSdk = flutter.targetSdkVersion` (`build.gradle.kts:39-40`). 값 24/36은 이전 회차 확인값이다. 이번 회차에는 값을 재확인하지 않았다.

### 8. 릴리스 빌드
- [AUTO-OK] 릴리스 APK 생성·서명: `app-release.apk` 89,106,995 B, 서명 확인(항목 4). `libmukmuk_bridge.so`가 `arm64-v8a`·`armeabi-v7a`·`x86_64` 3개 ABI로 포함됨(zip 목록 확인).
- [AUTO-OK] `cd app && flutter test` → `All tests passed!` 32건 (2026-11-04 재실행, exit 0). 직전 기록의 29건은 이번에 32건으로 바뀌었다(TTS 설치 안내 테스트 추가).
- 참고: `flutter build apk --release`는 이번 회차에 다시 실행하지 않았다. 위 APK 산출물과 서명은 현재 워킹트리 기준으로 확인했다. 배포 전 최종 빌드를 한 번 더 실행하는 것을 권한다.

### 9. TTS 설치 안내 · 음성 고지
- [AUTO-OK] 구현·테스트: 한국어 오프라인 음성이 없으면 발화를 생략하고 `오프라인 한국어 음성이 없어 음성 안내는 생략됩니다.`를 표시한다(`app/lib/nav/navigation_screen.dart:49`). 테스트 `app/test/tts/tts_install_banner_test.dart`. 커밋 `5f0c8fb`, 병합 `349bf26`.
- [MANUAL] 실기기에서 배너(안내 문구) 표시 확인. 항목 6의 권한 제거 후 동작 확인도 함께 한다.
- [USER] design 6절 5(미결) 확정: 이 문구를 배포용 고지로 쓸지, 음성 다운로드 안내를 추가할지.

### 10. 출처 표기 (OSM ODbL)
- [AUTO-OK] 앱 내 표기: 홈 화면 `app/lib/home_screen.dart:138`의 `© OpenStreetMap contributors`, 지도 스타일 `app/lib/map/mbtiles_style.dart:26`의 attribution.
- [USER] 공개 전 필수: ODbL 재배포 조건(데이터 팩 배포가 파생물 공개 의무에 해당하는지)을 법적으로 확인한다.
- [USER] 스토어 설명 또는 앱 내 라이선스 화면에 OSM 기여자 표기와 ODbL 고지를 넣을지 결정(design 6절 8).

### 11. 데이터 팩
- [AUTO-OK] 샘플 팩 무결성: 아래 `## 데이터 팩` 절. zip 내부 manifest의 크기·sha256과 `data/sample/`의 파일이 일치한다.
- [AUTO-OK] GitHub 초안 릴리스 존재: `pack-sample-2026.11`, `isDraft: true`, 자산 `sample.zip` 20,335,208 B, GitHub 자산 digest가 로컬 `data/sample.zip`의 sha256과 같다.
- [USER] 초안 릴리스 공개 전환 결정(샘플 팩은 테스트용이다. 이름에 "테스트용"이 들어 있음).
- [USER] 전국 팩 빌드(현재 샘플만 있음), CDN 업로드, 배포 URL 등록. 에이전트 범위 밖.

### 12. 기술 부채 표식
- [AUTO-OK] `app/lib`의 `TODO`·`FIXME`·`XXX`: 0건 (2026-11-04 재확인).
- [AUTO-OK] `core/`의 `TODO`·`FIXME`·`XXX`: 0건(직전 회차 확인). `ponytail:` 표식 3건(의도된 단순화, 상한 명시):
  - `core/core/src/matching/snap.rs:56` 에지 전수 선형 스캔 (전국 규모에서는 격자/KD 인덱스 필요)
  - `core/core/src/routing/ch_preprocess.rs:5` 정확한 edge-difference 우선순위는 전처리 시간이 문제 될 때 추가
  - `core/core/src/routing/path_decode.rs:244` 전국 규모에서는 공간 인덱스 필요
- 참고: `app/android/app/build.gradle.kts:35`의 `TODO` 1건은 항목 1에서 주석 삭제 대상으로 남겼다.

### 13. 실기기 MANUAL (재확인 대상)
- [MANUAL] 항목 9의 배너 표시, 항목 6 권한 제거 시 동작, 릴리스 APK 설치 후 지도·위치 동작. verify.md의 `MANUAL(승인)` 항목(F1~F10, KPI 4종)은 이 점검에서 다시 열지 않는다.

## 데이터 팩

- 상태: **샘플 팩(대전 지역) 기준.** 전국 팩은 아직 빌드하지 않았다. 전국 빌드와 전국 규모 KPI는 `MANUAL`이다(verify.md 회차 2).
- 위치: `data/sample/`(gitignore 대상), 배포 후보 zip `data/sample.zip`(gitignore 대상).
- `manifest.json` 값(zip 내부 manifest 기준):
  - `pack_version`: `2026.11`
  - `format_version`: `1`
  - `osm_date`: `2026-11-02`
  - `ngii`: `false` (NGII 수치지도 미사용)
  - `built_at`: `2026-11-04T01:17:41Z`
- 파일별 크기·sha256 (zip 내부 manifest 값 = `data/sample/manifest.json` 값):

| 파일 | 크기(B) | sha256 |
| --- | --- | --- |
| `map/korea.mbtiles` | 15,388,672 | `3df3510f3a3be797a8e282ecae0369b2d1e6227d1e371f8bf72ed4a815c7d48d` |
| `graph/korea.graph.bin` | 13,654,560 | `80421e3b9e8ccc33c377f84cc02f5ce15c1026510138fdf23018b50b422311ee` |
| `poi/korea.poi.sqlite` | 831,488 | `4f68f74bc8799f395d48e1b054200d75fb3160b6bad573f5f80216899be71f8e` |

- zip 파일: `data/sample.zip` 20,335,208 B, sha256 `35ea3d9cebed600fc27c3d8db71db7ca722f96e1b5da5b8c744d933d11e8e60a`. 초안 릴리스 자산의 digest와 같다.
- 원본 OSM 날짜: 2026-11-02
- 초안 릴리스: `pack-sample-2026.11`(Draft). 공개 전환 [USER].
- CDN 업로드: [USER] 미수행. 배포 전 사용자가 업로드하고 URL을 확정한다.
- 참고: 샘플 `mbtiles` 메타의 `bounds`/`center`는 대전 범위(`127.25,36.20,127.60,36.55`)라 설계 3.2절의 전국 값(`124.0,33.0,132.0,39.0`)과 다르다. 전국 팩에서 설계값을 지켜야 한다(verify.md 회차 1).

## 참고: 다른 문서 불일치 (이 점검 범위 밖)

- `docs/agent/verify.md:88` 회차 2 종합의 `MANUAL 9건 / MANUAL(승인) 4건`은 본문과 맞지 않는다. 본문에는 `MANUAL(승인)` 13건이 있다. 검증 담당이 정정해야 한다. 게이트 판정에는 영향이 없다.

## 조치 요약

- 에이전트가 할 수 있는 정비: `build.gradle.kts:35` 오래된 TODO 주석 삭제(코드 변경이므로 승인 후 실행).
- 다음 단계: USER 목록 처리 → 권한 결정 반영 후 `flutter build apk --release` 재실행 → 릴리스 병합 매니페스트 권한 재점검 → 실기기 MANUAL 확인.

## 데이터 팩 공개 배포 (Cloudflare R2, 2026-11-05)
- 버킷: `mukmuk-packs` (r2.dev 공개 접근 활성화)
- 공개 주소: `https://pub-b41149f0f441435e93b044e49cd215f2.r2.dev/`
- 올린 파일: `manifest.json`, `NOTICE.txt`, `map/korea.mbtiles`, `graph/korea.graph.bin`, `poi/korea.poi.sqlite` (샘플 팩 2026.11, 대전 범위)
- 검증: 5개 파일을 내려받아 sha256이 로컬 원본과 일치(MATCH). 공개 주소 HTTP 200, 크기 일치.
- 앱 빌드 인자: `--dart-define=MUKMUK_PACK_URL=https://pub-b41149f0f441435e93b044e49cd215f2.r2.dev/`
- 라이선스: ODbL 1.0 — NOTICE.txt와 manifest의 license·license_uri·attribution 필드로 고지. 공개 배포 조건은 docs/human/odbl-review.md 참고.
- USER: 법률 자문 여부 결정(벡터 타일 분류), GitHub 초안 릴리스(`pack-sample-2026.11`, 이전 zip 자산 포함) 정리 여부 결정.
- 미확인: 앱이 공개 주소에서 실제로 내려받는 흐름(Wi-Fi 연결 상태에서 자동 확인·다운로드)의 end-to-end 확인은 이번 회차에 하지 못함.
