//! R10/R11: FFI 계약 함수의 성공/실패 경로. 전역 엔진 상태 때문에 테스트를 하나로 묶는다.

use mukmuk_bridge::api::{self, types::*};
use mukmuk_core::fixtures;

fn block_on<F: std::future::Future>(f: F) -> F::Output {
    pollster::block_on(f)
}

#[test]
fn ffi_contract_flow() {
    // 1) 초기화 전에는 NotInitialized.
    let err = block_on(api::search_poi(
        "대전".into(),
        GeoPoint {
            lat: fixtures::A.lat,
            lon: fixtures::A.lon,
        },
        10.0,
        10,
    ))
    .expect_err("must fail before init");
    assert!(matches!(err, EngineError::NotInitialized), "got {err:?}");

    // 2) 없는 팩 → PackNotFound.
    let err =
        block_on(api::init_engine("Z:/definitely/not/a/pack".into())).expect_err("missing pack");
    assert!(matches!(err, EngineError::PackNotFound), "got {err:?}");

    // 3) 정상 팩 → EngineInfo.
    let dir = tempfile::tempdir().expect("tempdir");
    let pack_dir = dir.path().join("pack");
    fixtures::write_pack(&pack_dir).expect("fixture");
    let info = block_on(api::init_engine(pack_dir.to_string_lossy().into_owned())).expect("init");
    assert_eq!(info.pack_version, "2026.11");
    assert_eq!(info.format_version, 1);
    assert_eq!(info.node_count, 5);
    assert_eq!(info.poi_count, 2);

    // 4) 검색.
    let center = GeoPoint {
        lat: fixtures::A.lat,
        lon: fixtures::A.lon,
    };
    let results = block_on(api::search_poi("대전".into(), center, 10.0, 10)).expect("search");
    assert_eq!(results.len(), 2);
    let chosung = block_on(api::search_poi("ㄷㅈ".into(), center, 10.0, 10)).expect("chosung");
    assert_eq!(chosung.len(), 2);

    // 5) 경로 계획 (워커 스레드).
    let route = block_on(api::plan_route(
        GeoPoint {
            lat: fixtures::A.lat,
            lon: fixtures::A.lon,
        },
        GeoPoint {
            lat: fixtures::C.lat,
            lon: fixtures::C.lon,
        },
        TravelProfile::Car,
    ))
    .expect("plan_route");
    assert!(!route.polyline.is_empty());
    assert!(route.total_distance_m > 0.0);
    assert!(route.steps.iter().any(|s| s.maneuver == Maneuver::Depart));
    assert!(route.steps.iter().any(|s| s.maneuver == Maneuver::Arrive));

    // 6) 위치 갱신 + 칼만/스냅.
    let snapped = block_on(api::update_position(
        GeoPoint {
            lat: fixtures::A.lat,
            lon: fixtures::A.lon,
        },
        0.0,
        0.0,
        1_000,
    ))
    .expect("update");
    assert!(!snapped.off_route);
    assert!(snapped.distance_to_route_m < 30.0);

    // 7) 잘못된 입력은 EngineError로 전달.
    let err = block_on(api::update_position(
        GeoPoint {
            lat: 100.0,
            lon: 0.0,
        },
        0.0,
        0.0,
        2_000,
    ))
    .expect_err("bad coordinate");
    assert!(matches!(err, EngineError::InvalidInput(_)));

    // 8) 포맷 버전 불일치 팩 → FormatMismatch (기존 엔진은 유지).
    let bad_dir = dir.path().join("bad-pack");
    std::fs::create_dir_all(&bad_dir).expect("mkdir");
    std::fs::write(
        bad_dir.join("manifest.json"),
        r#"{"format_version":2,"pack_version":"x","osm_date":"y","files":{}}"#,
    )
    .expect("manifest");
    let err = block_on(api::init_engine(bad_dir.to_string_lossy().into_owned()))
        .expect_err("format mismatch");
    assert!(matches!(err, EngineError::FormatMismatch(_)), "got {err:?}");
}
