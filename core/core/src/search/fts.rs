//! POI FTS5 검색 + 초성 + 반경/거리 정렬 (`docs/agent/design.md` 3.4절).

use std::path::Path;

use rusqlite::{Connection, OpenFlags};

use crate::error::EngineError;
use crate::types::{haversine_m, GeoPoint, PoiResult};

/// `poi.sqlite`의 고유 application_id ("MKMK").
pub const POI_APPLICATION_ID: i32 = 0x4D55_4B4D;
pub const POI_USER_VERSION: i32 = 1;

const METERS_PER_DEG_LAT: f64 = 111_320.0;

fn is_chosung_query(query: &str) -> bool {
    let mut any = false;
    for c in query.chars() {
        if c.is_whitespace() {
            continue;
        }
        any = true;
        if !('\u{3131}'..='\u{314E}').contains(&c) {
            return false;
        }
    }
    any
}

fn escape_fts(query: &str) -> String {
    query.replace('"', "\"\"")
}

fn fts_match_expression(query: &str) -> String {
    let escaped = escape_fts(query.trim());
    if is_chosung_query(query) {
        format!("name_chosung : \"{escaped}\"*")
    } else {
        // name/addr/category 전체 컬럼에 대한 prefix 매치.
        format!("\"{escaped}\"*")
    }
}

fn open_checked(db_path: &Path) -> Result<Connection, EngineError> {
    if !db_path.is_file() {
        return Err(EngineError::PackNotFound);
    }
    let conn = Connection::open_with_flags(db_path, OpenFlags::SQLITE_OPEN_READ_ONLY)
        .map_err(|e| EngineError::SearchFailed(format!("open poi db: {e}")))?;
    let app_id: i32 = conn
        .query_row("PRAGMA application_id", [], |row| row.get(0))
        .map_err(|e| EngineError::SearchFailed(format!("application_id: {e}")))?;
    let user_version: i32 = conn
        .query_row("PRAGMA user_version", [], |row| row.get(0))
        .map_err(|e| EngineError::SearchFailed(format!("user_version: {e}")))?;
    if app_id != POI_APPLICATION_ID || user_version != POI_USER_VERSION {
        return Err(EngineError::FormatMismatch(format!(
            "poi db app_id={app_id:#x} user_version={user_version} (expected {POI_APPLICATION_ID:#x}/{POI_USER_VERSION})"
        )));
    }
    // 설계 4절: sqlite 페이지 캐시 상한 16MB.
    conn.execute_batch("PRAGMA cache_size = -16000;")
        .map_err(|e| EngineError::SearchFailed(format!("cache_size: {e}")))?;
    Ok(conn)
}

/// `init_engine`에서 팩의 POI DB 스키마 버전을 검사한다.
pub fn validate_poi_db(db_path: &Path) -> Result<(), EngineError> {
    open_checked(db_path).map(|_| ())
}

/// POI 총 개수(EngineInfo용).
pub fn poi_count(db_path: &Path) -> Result<u64, EngineError> {
    let conn = open_checked(db_path)?;
    let count: i64 = conn
        .query_row("SELECT COUNT(*) FROM poi", [], |row| row.get(0))
        .map_err(|e| EngineError::SearchFailed(format!("poi count: {e}")))?;
    Ok(count.max(0) as u64)
}

/// 반경 내 POI를 거리 오름차순으로 최대 `limit`개 반환한다.
pub fn search_poi(
    db_path: &Path,
    query: &str,
    center: GeoPoint,
    radius_km: f64,
    limit: u32,
) -> Result<Vec<PoiResult>, EngineError> {
    let trimmed = query.trim();
    if trimmed.is_empty() {
        return Err(EngineError::InvalidInput("empty search query".into()));
    }
    if !radius_km.is_finite() || radius_km <= 0.0 {
        return Err(EngineError::InvalidInput(
            "radius_km must be positive".into(),
        ));
    }
    if limit == 0 {
        return Err(EngineError::InvalidInput("limit must be positive".into()));
    }
    if !(-90.0..=90.0).contains(&center.lat) || !(-180.0..=180.0).contains(&center.lon) {
        return Err(EngineError::InvalidInput("center out of range".into()));
    }

    let conn = open_checked(db_path)?;
    let radius_m = radius_km * 1000.0;
    let (lat_lo, lat_hi, lon_lo, lon_hi) = bbox_e7(center, radius_m);
    let match_expr = fts_match_expression(trimmed);

    let mut stmt = conn
        .prepare(
            "SELECT p.id, p.name, p.category, p.addr, p.lat_e7, p.lon_e7
             FROM poi_fts JOIN poi p ON p.id = poi_fts.rowid
             WHERE poi_fts MATCH ?1
               AND p.lat_e7 BETWEEN ?2 AND ?3
               AND p.lon_e7 BETWEEN ?4 AND ?5",
        )
        .map_err(|e| EngineError::SearchFailed(format!("prepare: {e}")))?;
    let rows = stmt
        .query_map(
            rusqlite::params![match_expr, lat_lo, lat_hi, lon_lo, lon_hi],
            |row| {
                let lat_e7: i64 = row.get(4)?;
                let lon_e7: i64 = row.get(5)?;
                Ok(PoiResult {
                    id: row.get::<_, i64>(0)? as u64,
                    name: row.get(1)?,
                    category: row.get(2)?,
                    addr: row.get(3)?,
                    point: GeoPoint::new(lat_e7 as f64 / 1e7, lon_e7 as f64 / 1e7),
                    distance_m: 0.0,
                })
            },
        )
        .map_err(|e| EngineError::SearchFailed(format!("query: {e}")))?;

    let mut results: Vec<PoiResult> = Vec::new();
    for row in rows {
        let mut poi = row.map_err(|e| EngineError::SearchFailed(format!("row: {e}")))?;
        poi.distance_m = haversine_m(center, poi.point);
        if poi.distance_m <= radius_m {
            results.push(poi);
        }
    }
    results.sort_by(|a, b| {
        a.distance_m
            .partial_cmp(&b.distance_m)
            .unwrap_or(std::cmp::Ordering::Equal)
            .then_with(|| a.id.cmp(&b.id))
    });
    results.truncate(limit as usize);
    Ok(results)
}

/// 지도 탭 지점 주변 POI를 거리 오름차순으로 최대 `limit`개 반환한다(FTS 없이 좌표 인덱스만 사용).
/// 지도 탭 식별 용도이므로 반경은 작게(수백 m) 준다.
pub fn nearby_poi(
    db_path: &Path,
    center: GeoPoint,
    radius_km: f64,
    limit: u32,
) -> Result<Vec<PoiResult>, EngineError> {
    if !radius_km.is_finite() || radius_km <= 0.0 {
        return Err(EngineError::InvalidInput(
            "radius_km must be positive".into(),
        ));
    }
    if limit == 0 {
        return Err(EngineError::InvalidInput("limit must be positive".into()));
    }
    if !(-90.0..=90.0).contains(&center.lat) || !(-180.0..=180.0).contains(&center.lon) {
        return Err(EngineError::InvalidInput("center out of range".into()));
    }

    let conn = open_checked(db_path)?;
    let radius_m = radius_km * 1000.0;
    let (lat_lo, lat_hi, lon_lo, lon_hi) = bbox_e7(center, radius_m);
    let mut stmt = conn
        .prepare(
            "SELECT p.id, p.name, p.category, p.addr, p.lat_e7, p.lon_e7
             FROM poi p
             WHERE p.lat_e7 BETWEEN ?1 AND ?2 AND p.lon_e7 BETWEEN ?3 AND ?4",
        )
        .map_err(|e| EngineError::SearchFailed(format!("prepare: {e}")))?;
    let rows = stmt
        .query_map(rusqlite::params![lat_lo, lat_hi, lon_lo, lon_hi], |row| {
            let lat_e7: i64 = row.get(4)?;
            let lon_e7: i64 = row.get(5)?;
            Ok(PoiResult {
                id: row.get::<_, i64>(0)? as u64,
                name: row.get(1)?,
                category: row.get(2)?,
                addr: row.get(3)?,
                point: GeoPoint::new(lat_e7 as f64 / 1e7, lon_e7 as f64 / 1e7),
                distance_m: 0.0,
            })
        })
        .map_err(|e| EngineError::SearchFailed(format!("query: {e}")))?;

    let mut results: Vec<PoiResult> = Vec::new();
    for row in rows {
        let mut poi = row.map_err(|e| EngineError::SearchFailed(format!("row: {e}")))?;
        poi.distance_m = haversine_m(center, poi.point);
        if poi.distance_m <= radius_m {
            results.push(poi);
        }
    }
    results.sort_by(|a, b| {
        a.distance_m
            .partial_cmp(&b.distance_m)
            .unwrap_or(std::cmp::Ordering::Equal)
            .then_with(|| a.id.cmp(&b.id))
    });
    results.truncate(limit as usize);
    Ok(results)
}

/// 중심과 반경(m)으로 E7 정수 bbox (lat_lo, lat_hi, lon_lo, lon_hi)를 만든다.
fn bbox_e7(center: GeoPoint, radius_m: f64) -> (i64, i64, i64, i64) {
    let lat_delta = radius_m / METERS_PER_DEG_LAT;
    let cos_lat = center.lat.to_radians().cos().abs().max(1e-9);
    let lon_delta = radius_m / (METERS_PER_DEG_LAT * cos_lat);
    (
        ((center.lat - lat_delta) * 1e7) as i64,
        ((center.lat + lat_delta) * 1e7) as i64,
        ((center.lon - lon_delta) * 1e7) as i64,
        ((center.lon + lon_delta) * 1e7) as i64,
    )
}

#[cfg(test)]
mod tests {
    use super::*;
    use rusqlite::Connection;

    #[test]
    fn nearby_returns_closest_first_and_respects_radius() {
        let (_d, path) = fixture();
        // 대전역(id 1)과 대전카페(id 2) 근처. 서울역은 수백 km 밖.
        let out = nearby_poi(&path, daejeon(), 1.0, 10).expect("nearby");
        let ids: Vec<u64> = out.iter().map(|p| p.id).collect();
        assert_eq!(ids, vec![1, 2]);
        assert!(out[0].distance_m <= out[1].distance_m);
        assert!(out.iter().all(|p| p.distance_m <= 1000.0));
    }

    #[test]
    fn nearby_limit_and_empty_area() {
        let (_d, path) = fixture();
        assert_eq!(
            nearby_poi(&path, daejeon(), 1.0, 1).expect("limit").len(),
            1
        );
        let far = GeoPoint::new(35.0, 129.0);
        assert!(nearby_poi(&path, far, 0.3, 10).expect("empty").is_empty());
    }

    #[test]
    fn nearby_rejects_invalid_input() {
        let (_d, path) = fixture();
        assert!(matches!(
            nearby_poi(&path, daejeon(), 0.0, 10),
            Err(EngineError::InvalidInput(_))
        ));
        assert!(matches!(
            nearby_poi(&path, daejeon(), 1.0, 0),
            Err(EngineError::InvalidInput(_))
        ));
        assert!(matches!(
            nearby_poi(&path, GeoPoint::new(95.0, 0.0), 1.0, 10),
            Err(EngineError::InvalidInput(_))
        ));
    }

    fn fixture() -> (tempfile::TempDir, std::path::PathBuf) {
        let dir = tempfile::tempdir().expect("tempdir");
        let path = dir.path().join("korea.poi.sqlite");
        let conn = Connection::open(&path).expect("open");
        conn.execute_batch(&format!(
            "PRAGMA application_id = {POI_APPLICATION_ID};
             PRAGMA user_version = 1;
             CREATE TABLE poi (
               id INTEGER PRIMARY KEY,
               name TEXT NOT NULL,
               name_chosung TEXT NOT NULL,
               category TEXT NOT NULL,
               addr TEXT,
               lat_e7 INTEGER NOT NULL,
               lon_e7 INTEGER NOT NULL,
               importance INTEGER NOT NULL DEFAULT 0
             );
             CREATE INDEX idx_poi_latlon ON poi(lat_e7, lon_e7);
             CREATE VIRTUAL TABLE poi_fts USING fts5(
               name, name_chosung, addr, category,
               content='poi', content_rowid='id',
               tokenize='unicode61 remove_diacritics 2'
             );
             INSERT INTO poi(id,name,name_chosung,category,addr,lat_e7,lon_e7,importance) VALUES
               (1,'대전역','ㄷㅈㅇ','transit','대전 동구',363_320_000,1274_340_000,10),
               (2,'대전카페','ㄷㅈㅋㅍ','cafe','대전 중구',363_400_000,1274_350_000,5),
               (3,'서울역','ㅅㅇㅇ','transit','서울 용산구',375_550_000,1269_700_000,10);
             INSERT INTO poi_fts(poi_fts) VALUES('rebuild');"
        ))
        .expect("schema");
        (dir, path)
    }

    fn daejeon() -> GeoPoint {
        GeoPoint::new(36.332, 127.434)
    }

    #[test]
    fn prefix_search_orders_by_distance() {
        let (_d, path) = fixture();
        let out = search_poi(&path, "대전", daejeon(), 10.0, 10).expect("search");
        assert_eq!(out.len(), 2);
        assert_eq!(out[0].id, 1);
        assert_eq!(out[1].id, 2);
        assert!(out[0].distance_m <= out[1].distance_m);
    }

    #[test]
    fn chosung_search_works() {
        let (_d, path) = fixture();
        let out = search_poi(&path, "ㄷㅈ", daejeon(), 10.0, 10).expect("search");
        let ids: Vec<u64> = out.iter().map(|p| p.id).collect();
        assert_eq!(ids, vec![1, 2]);
    }

    #[test]
    fn radius_filters_far_results() {
        let (_d, path) = fixture();
        assert!(search_poi(&path, "서울", daejeon(), 10.0, 10)
            .expect("search")
            .is_empty());
        let out = search_poi(&path, "서울", daejeon(), 300.0, 10).expect("search");
        assert_eq!(out.len(), 1);
        assert_eq!(out[0].id, 3);
    }

    #[test]
    fn limit_is_honoured() {
        let (_d, path) = fixture();
        let out = search_poi(&path, "대전", daejeon(), 10.0, 1).expect("search");
        assert_eq!(out.len(), 1);
    }

    #[test]
    fn rejects_invalid_input() {
        let (_d, path) = fixture();
        assert!(matches!(
            search_poi(&path, "  ", daejeon(), 10.0, 10),
            Err(EngineError::InvalidInput(_))
        ));
        assert!(matches!(
            search_poi(&path, "대전", daejeon(), 0.0, 10),
            Err(EngineError::InvalidInput(_))
        ));
    }

    #[test]
    fn rejects_wrong_schema_version() {
        let dir = tempfile::tempdir().expect("tempdir");
        let path = dir.path().join("bad.sqlite");
        Connection::open(&path).expect("open");
        assert!(matches!(
            search_poi(&path, "대전", daejeon(), 10.0, 10),
            Err(EngineError::FormatMismatch(_))
        ));
    }

    #[test]
    fn chosung_detection() {
        assert!(is_chosung_query("ㄷㅈㅇ"));
        assert!(is_chosung_query("ㄱ"));
        assert!(!is_chosung_query("대전"));
        assert!(!is_chosung_query("ㄷㅈa"));
        assert!(!is_chosung_query("   "));
    }
}
