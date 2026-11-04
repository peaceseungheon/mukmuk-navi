//! FFI 경계 타입 (`docs/agent/design.md` 2.1절). Dart 코드젠의 입력이므로
//! 이름·필드 순서를 바꾸지 않는다.

use mukmuk_core::types as core;

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct GeoPoint {
    pub lat: f64,
    pub lon: f64,
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct BBox {
    pub min_lon: f64,
    pub min_lat: f64,
    pub max_lon: f64,
    pub max_lat: f64,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TravelProfile {
    Car,
    Foot,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Maneuver {
    Depart,
    Left,
    Right,
    SharpLeft,
    SharpRight,
    Uturn,
    Straight,
    MergeLeft,
    MergeRight,
    Arrive,
}

#[derive(Debug, Clone, PartialEq)]
pub struct RouteStep {
    pub maneuver: Maneuver,
    pub road_name: String,
    pub point: GeoPoint,
    pub distance_m: f64,
    pub duration_s: f64,
}

#[derive(Debug, Clone, PartialEq)]
pub struct Route {
    pub polyline: Vec<GeoPoint>,
    pub steps: Vec<RouteStep>,
    pub total_distance_m: f64,
    pub total_duration_s: f64,
}

#[derive(Debug, Clone, PartialEq)]
pub struct SnappedPosition {
    pub point: GeoPoint,
    pub road_id: u64,
    pub distance_to_route_m: f64,
    pub off_route: bool,
}

#[derive(Debug, Clone, PartialEq)]
pub struct PoiResult {
    pub id: u64,
    pub name: String,
    pub category: String,
    pub addr: Option<String>,
    pub point: GeoPoint,
    pub distance_m: f64,
}

#[derive(Debug, Clone, PartialEq)]
pub struct EngineInfo {
    pub pack_version: String,
    pub osm_date: String,
    pub format_version: u32,
    pub node_count: u64,
    pub poi_count: u64,
    pub bbox: BBox,
}

#[derive(Debug, Clone, PartialEq)]
pub enum NavigationEvent {
    Rerouted(Route),
    Instruction(RouteStep),
    Arrived,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum EngineError {
    NotInitialized,
    PackNotFound,
    FormatMismatch(String),
    GraphCorrupt(String),
    SearchFailed(String),
    RoutingFailed(String),
    InvalidInput(String),
    Internal(String),
}

impl From<GeoPoint> for core::GeoPoint {
    fn from(p: GeoPoint) -> Self {
        core::GeoPoint::new(p.lat, p.lon)
    }
}

impl From<core::GeoPoint> for GeoPoint {
    fn from(p: core::GeoPoint) -> Self {
        Self {
            lat: p.lat,
            lon: p.lon,
        }
    }
}

impl From<core::BBox> for BBox {
    fn from(b: core::BBox) -> Self {
        Self {
            min_lon: b.min_lon,
            min_lat: b.min_lat,
            max_lon: b.max_lon,
            max_lat: b.max_lat,
        }
    }
}

impl From<core::TravelProfile> for TravelProfile {
    fn from(p: core::TravelProfile) -> Self {
        match p {
            core::TravelProfile::Car => TravelProfile::Car,
            core::TravelProfile::Foot => TravelProfile::Foot,
        }
    }
}

impl From<TravelProfile> for core::TravelProfile {
    fn from(p: TravelProfile) -> Self {
        match p {
            TravelProfile::Car => core::TravelProfile::Car,
            TravelProfile::Foot => core::TravelProfile::Foot,
        }
    }
}

impl From<core::Maneuver> for Maneuver {
    fn from(m: core::Maneuver) -> Self {
        match m {
            core::Maneuver::Depart => Maneuver::Depart,
            core::Maneuver::Left => Maneuver::Left,
            core::Maneuver::Right => Maneuver::Right,
            core::Maneuver::SharpLeft => Maneuver::SharpLeft,
            core::Maneuver::SharpRight => Maneuver::SharpRight,
            core::Maneuver::Uturn => Maneuver::Uturn,
            core::Maneuver::Straight => Maneuver::Straight,
            core::Maneuver::MergeLeft => Maneuver::MergeLeft,
            core::Maneuver::MergeRight => Maneuver::MergeRight,
            core::Maneuver::Arrive => Maneuver::Arrive,
        }
    }
}

impl From<core::RouteStep> for RouteStep {
    fn from(s: core::RouteStep) -> Self {
        Self {
            maneuver: s.maneuver.into(),
            road_name: s.road_name,
            point: s.point.into(),
            distance_m: s.distance_m,
            duration_s: s.duration_s,
        }
    }
}

impl From<core::Route> for Route {
    fn from(r: core::Route) -> Self {
        Self {
            polyline: r.polyline.into_iter().map(Into::into).collect(),
            steps: r.steps.into_iter().map(Into::into).collect(),
            total_distance_m: r.total_distance_m,
            total_duration_s: r.total_duration_s,
        }
    }
}

impl From<core::SnappedPosition> for SnappedPosition {
    fn from(s: core::SnappedPosition) -> Self {
        Self {
            point: s.point.into(),
            road_id: s.road_id,
            distance_to_route_m: s.distance_to_route_m,
            off_route: s.off_route,
        }
    }
}

impl From<core::PoiResult> for PoiResult {
    fn from(p: core::PoiResult) -> Self {
        Self {
            id: p.id,
            name: p.name,
            category: p.category,
            addr: p.addr,
            point: p.point.into(),
            distance_m: p.distance_m,
        }
    }
}

impl From<core::EngineInfo> for EngineInfo {
    fn from(i: core::EngineInfo) -> Self {
        Self {
            pack_version: i.pack_version,
            osm_date: i.osm_date,
            format_version: i.format_version,
            node_count: i.node_count,
            poi_count: i.poi_count,
            bbox: i.bbox.into(),
        }
    }
}

pub(crate) fn navigation_event_from_core(event: core::NavigationEvent) -> NavigationEvent {
    match event {
        core::NavigationEvent::Rerouted(route) => NavigationEvent::Rerouted(route.into()),
        core::NavigationEvent::Instruction(step) => NavigationEvent::Instruction(step.into()),
        core::NavigationEvent::Arrived => NavigationEvent::Arrived,
    }
}

impl From<mukmuk_core::EngineError> for EngineError {
    fn from(e: mukmuk_core::EngineError) -> Self {
        match e {
            mukmuk_core::EngineError::NotInitialized => EngineError::NotInitialized,
            mukmuk_core::EngineError::PackNotFound => EngineError::PackNotFound,
            mukmuk_core::EngineError::FormatMismatch(s) => EngineError::FormatMismatch(s),
            mukmuk_core::EngineError::GraphCorrupt(s) => EngineError::GraphCorrupt(s),
            mukmuk_core::EngineError::SearchFailed(s) => EngineError::SearchFailed(s),
            mukmuk_core::EngineError::RoutingFailed(s) => EngineError::RoutingFailed(s),
            mukmuk_core::EngineError::InvalidInput(s) => EngineError::InvalidInput(s),
            mukmuk_core::EngineError::Internal(s) => EngineError::Internal(s),
        }
    }
}
