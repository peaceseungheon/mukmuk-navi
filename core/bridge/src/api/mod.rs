//! FRB API 레이어 (`docs/agent/design.md` 2.2절). 시그니처 고정.

pub mod types;

use std::path::Path;

use flutter_rust_bridge::frb;

use self::types::{
    EngineError, EngineInfo, GeoPoint, NavigationEvent, PoiResult, Route, SnappedPosition,
    TravelProfile,
};
use crate::engine::{self, EventSink};
use crate::frb_generated::StreamSink;

struct FrbSink(StreamSink<NavigationEvent>);

/// flutter_rust_bridge:ignore
impl EventSink for FrbSink {
    fn send(&self, event: mukmuk_core::types::NavigationEvent) {
        let _ = self.0.add(types::navigation_event_from_core(event));
    }
}

#[frb]
pub async fn init_engine(pack_dir: String) -> Result<EngineInfo, EngineError> {
    let (engine, info) = engine::Engine::open(Path::new(&pack_dir))?;
    engine::install(engine);
    Ok(info.into())
}

#[frb]
pub async fn search_poi(
    query: String,
    center: GeoPoint,
    radius_km: f64,
    limit: u32,
) -> Result<Vec<PoiResult>, EngineError> {
    let engine = engine::current()?;
    let results = engine.search(&query, center.into(), radius_km, limit)?;
    Ok(results.into_iter().map(Into::into).collect())
}

/// 지도 탭 지점 주변 POI(거리순). 설계 2.2절에 추가된 함수(기존 시그니처는 변경 없음).
#[frb]
pub async fn nearby_poi(
    center: GeoPoint,
    radius_km: f64,
    limit: u32,
) -> Result<Vec<PoiResult>, EngineError> {
    let engine = engine::current()?;
    let results = engine.nearby(center.into(), radius_km, limit)?;
    Ok(results.into_iter().map(Into::into).collect())
}

#[frb]
pub async fn plan_route(
    start: GeoPoint,
    end: GeoPoint,
    profile: TravelProfile,
) -> Result<Route, EngineError> {
    let engine = engine::current()?;
    let route = engine.plan_route(start.into(), end.into(), profile.into())?;
    Ok(route.into())
}

#[frb]
pub async fn subscribe_navigation(sink: StreamSink<NavigationEvent>) -> Result<(), EngineError> {
    let engine = engine::current()?;
    engine.subscribe(Box::new(FrbSink(sink)));
    Ok(())
}

#[frb]
pub async fn update_position(
    pos: GeoPoint,
    speed_mps: f64,
    heading_deg: f64,
    t_ms: u64,
) -> Result<SnappedPosition, EngineError> {
    let engine = engine::current()?;
    let snapped = engine.update_position(pos.into(), speed_mps, heading_deg, t_ms)?;
    Ok(snapped.into())
}
