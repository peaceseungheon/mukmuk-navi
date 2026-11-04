//! FFI 경계에서 그대로 쓰는 값 타입. `docs/agent/design.md` 2.1절과 1:1 대응한다.

/// WGS84 도(degrees).
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct GeoPoint {
    pub lat: f64,
    pub lon: f64,
}

impl GeoPoint {
    pub const fn new(lat: f64, lon: f64) -> Self {
        Self { lat, lon }
    }
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

#[derive(Debug, Clone, PartialEq, Default)]
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

/// 두 지점 사이 하버사인 거리(미터).
pub fn haversine_m(a: GeoPoint, b: GeoPoint) -> f64 {
    const R: f64 = 6_371_000.0;
    let (lat1, lat2) = (a.lat.to_radians(), b.lat.to_radians());
    let dlat = (b.lat - a.lat).to_radians();
    let dlon = (b.lon - a.lon).to_radians();
    let h = (dlat / 2.0).sin().powi(2) + lat1.cos() * lat2.cos() * (dlon / 2.0).sin().powi(2);
    2.0 * R * h.sqrt().asin()
}

/// 구면 베어링(도, 0=북, 90=동).
pub fn bearing_deg(a: GeoPoint, b: GeoPoint) -> f64 {
    let (lat1, lat2) = (a.lat.to_radians(), b.lat.to_radians());
    let dlon = (b.lon - a.lon).to_radians();
    let y = dlon.sin() * lat2.cos();
    let x = lat1.cos() * lat2.sin() - lat1.sin() * lat2.cos() * dlon.cos();
    y.atan2(x).to_degrees().rem_euclid(360.0)
}
