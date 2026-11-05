/// 앱 상수. 팩 경로는 빌드 시 `--dart-define=MUKMUK_PACK_DIR=<팩 디렉터리>`로 주입한다.
const String kPackDir = String.fromEnvironment('MUKMUK_PACK_DIR');

/// 데이터 팩 서버 주소(`--dart-define=MUKMUK_PACK_URL=https://.../`). 비어 있으면 업데이트 기능을 숨긴다.
const String kPackUrl = String.fromEnvironment('MUKMUK_PACK_URL');

/// 검색 기본 반경(design.md 6절 2번: KPI 50km 기준으로 기본값 확정 전까지 50km).
const double kDefaultSearchRadiusKm = 50;

const int kSearchLimit = 50;

/// 위치 갱신 상한 10Hz (design.md 2.3절 5번, 4절 프레임 예산).
const Duration kPositionMinInterval = Duration(milliseconds: 100);

/// 모의 주행 주기(2Hz). 실 GPS 대신 경로 정점을 따라 위치를 흘려보낸다.
const Duration kSimulationInterval = Duration(milliseconds: 500);

/// 모의 주행 고정 속도(m/s). 정점 간격 기반 속도 보간은 하지 않는다.
const double kSimulationSpeedMps = 14;

/// 출발지 기본값(대전 시청). GPS 위치가 없을 때 사용.
const double kDefaultOriginLat = 36.3504;
const double kDefaultOriginLon = 127.3845;

/// 지도 초기 중심(대전, 샘플 팩 범위 안).
const double kMapInitialLat = 36.3504;
const double kMapInitialLon = 127.3845;
const double kMapInitialZoom = 12;
