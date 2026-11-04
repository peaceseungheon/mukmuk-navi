//! 4차원 등속도 칼만 필터(동/북 위치 + 속도). 고정 크기 배열만 사용한다.

use crate::types::GeoPoint;

/// 위도 1도의 미터 근사.
const METERS_PER_DEG_LAT: f64 = 111_320.0;

#[derive(Debug, Clone)]
pub struct KalmanFilter {
    origin_lat: f64,
    origin_lon: f64,
    x: [f64; 4],
    p: [[f64; 4]; 4],
    /// 가속도 잡음 분산(m²/s³).
    process_noise: f64,
    /// 측정 잡음 분산(m²).
    measurement_noise: f64,
    initialized: bool,
}

impl KalmanFilter {
    pub fn new(initial: GeoPoint) -> Self {
        Self {
            origin_lat: initial.lat,
            origin_lon: initial.lon,
            x: [0.0; 4],
            // 초기 위치 불확실성 100m², 속도 25(m/s)².
            p: [
                [100.0, 0.0, 0.0, 0.0],
                [0.0, 100.0, 0.0, 0.0],
                [0.0, 0.0, 25.0, 0.0],
                [0.0, 0.0, 0.0, 25.0],
            ],
            process_noise: 0.5,
            measurement_noise: 25.0,
            initialized: true,
        }
    }

    pub fn reset(&mut self, point: GeoPoint) {
        self.origin_lat = point.lat;
        self.origin_lon = point.lon;
        self.x = [0.0; 4];
        self.initialized = true;
    }

    pub fn with_noise(mut self, process_noise: f64, measurement_noise: f64) -> Self {
        if process_noise > 0.0 {
            self.process_noise = process_noise;
        }
        if measurement_noise > 0.0 {
            self.measurement_noise = measurement_noise;
        }
        self
    }

    fn meters_per_deg_lon(&self) -> f64 {
        let c = self.origin_lat.to_radians().cos();
        if c.abs() < 1e-9 {
            METERS_PER_DEG_LAT
        } else {
            METERS_PER_DEG_LAT * c
        }
    }

    fn to_local(&self, p: GeoPoint) -> [f64; 2] {
        [
            (p.lon - self.origin_lon) * self.meters_per_deg_lon(),
            (p.lat - self.origin_lat) * METERS_PER_DEG_LAT,
        ]
    }

    fn to_geo(&self, east: f64, north: f64) -> GeoPoint {
        GeoPoint::new(
            self.origin_lat + north / METERS_PER_DEG_LAT,
            self.origin_lon + east / self.meters_per_deg_lon(),
        )
    }

    /// 측정값으로 상태를 갱신하고 필터된 위치를 돌려준다. `dt_s`는 이전 갱신과의 간격.
    pub fn update(&mut self, measurement: GeoPoint, dt_s: f64) -> GeoPoint {
        if !self.initialized {
            self.reset(measurement);
            return measurement;
        }
        let dt = dt_s.clamp(0.001, 10.0);
        let f = [
            [1.0, 0.0, dt, 0.0],
            [0.0, 1.0, 0.0, dt],
            [0.0, 0.0, 1.0, 0.0],
            [0.0, 0.0, 0.0, 1.0],
        ];
        self.predict(&f, dt);
        let z = self.to_local(measurement);
        self.correct(z);
        self.to_geo(self.x[0], self.x[1])
    }

    fn predict(&mut self, f: &[[f64; 4]; 4], dt: f64) {
        self.x = mat_vec(f, &self.x);
        let ft = transpose(f);
        let fp = mat_mul(f, &self.p);
        let mut p = mat_mul(&fp, &ft);
        // 백색 가속도 잡음 모델.
        let q = self.process_noise;
        let dt2 = dt * dt;
        let dt3 = dt2 * dt;
        p[0][0] += q * dt3 / 3.0;
        p[1][1] += q * dt3 / 3.0;
        p[2][2] += q * dt;
        p[3][3] += q * dt;
        p[0][2] += q * dt2 / 2.0;
        p[2][0] += q * dt2 / 2.0;
        p[1][3] += q * dt2 / 2.0;
        p[3][1] += q * dt2 / 2.0;
        self.p = p;
    }

    fn correct(&mut self, z: [f64; 2]) {
        // H = [I2 | 0]
        let s00 = self.p[0][0] + self.measurement_noise;
        let s01 = self.p[0][1];
        let s10 = self.p[1][0];
        let s11 = self.p[1][1] + self.measurement_noise;
        let det = s00 * s11 - s01 * s10;
        if det.abs() < 1e-12 {
            return;
        }
        let inv_det = 1.0 / det;
        let s_inv = [
            [s11 * inv_det, -s01 * inv_det],
            [-s10 * inv_det, s00 * inv_det],
        ];
        // K = P Hᵀ S⁻¹ (4x2)
        let mut k = [[0.0f64; 2]; 4];
        for (row, krow) in k.iter_mut().enumerate() {
            krow[0] = self.p[row][0] * s_inv[0][0] + self.p[row][1] * s_inv[1][0];
            krow[1] = self.p[row][0] * s_inv[0][1] + self.p[row][1] * s_inv[1][1];
        }
        let innovation = [z[0] - self.x[0], z[1] - self.x[1]];
        for (i, ki) in k.iter().enumerate() {
            self.x[i] += ki[0] * innovation[0] + ki[1] * innovation[1];
        }
        // P = (I - K H) P
        let mut ikh = identity4();
        for i in 0..4 {
            ikh[i][0] -= k[i][0];
            ikh[i][1] -= k[i][1];
        }
        self.p = mat_mul(&ikh, &self.p);
    }
}

fn identity4() -> [[f64; 4]; 4] {
    let mut m = [[0.0; 4]; 4];
    for (i, row) in m.iter_mut().enumerate() {
        row[i] = 1.0;
    }
    m
}

fn mat_vec(a: &[[f64; 4]; 4], v: &[f64; 4]) -> [f64; 4] {
    let mut out = [0.0; 4];
    for (i, row) in a.iter().enumerate() {
        out[i] = row.iter().zip(v.iter()).map(|(x, y)| x * y).sum();
    }
    out
}

fn mat_mul(a: &[[f64; 4]; 4], b: &[[f64; 4]; 4]) -> [[f64; 4]; 4] {
    let mut out = [[0.0; 4]; 4];
    for (i, out_row) in out.iter_mut().enumerate() {
        for (j, cell) in out_row.iter_mut().enumerate() {
            *cell = (0..4).map(|k| a[i][k] * b[k][j]).sum();
        }
    }
    out
}

fn transpose(a: &[[f64; 4]; 4]) -> [[f64; 4]; 4] {
    let mut out = [[0.0; 4]; 4];
    for (i, row) in a.iter().enumerate() {
        for (j, cell) in row.iter().enumerate() {
            out[j][i] = *cell;
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    fn lcg(state: &mut u64) -> f64 {
        *state = state
            .wrapping_mul(6364136223846793005)
            .wrapping_add(1442695040888963407);
        // [-1, 1)
        ((*state >> 33) as f64 / (1u64 << 31) as f64) * 2.0 - 1.0
    }

    #[test]
    fn reduces_position_error_variance() {
        let start = GeoPoint::new(36.0, 127.0);
        let mut filter = KalmanFilter::new(start);
        let mut state = 99u64;
        let mut raw_sq = 0.0;
        let mut filtered_sq = 0.0;
        let mut samples = 0;
        for i in 0..200 {
            // 동쪽으로 10 m/s.
            let truth = GeoPoint::new(36.0, 127.0 + (i as f64 * 10.0) / 98_000.0);
            let noisy = GeoPoint::new(
                truth.lat + lcg(&mut state) * 0.00009,
                truth.lon + lcg(&mut state) * 0.00009,
            );
            let filtered = filter.update(noisy, 1.0);
            if i >= 20 {
                raw_sq += crate::types::haversine_m(noisy, truth).powi(2);
                filtered_sq += crate::types::haversine_m(filtered, truth).powi(2);
                samples += 1;
            }
        }
        let raw_var = raw_sq / samples as f64;
        let filtered_var = filtered_sq / samples as f64;
        println!("raw variance {raw_var:.2} filtered variance {filtered_var:.2}");
        assert!(
            filtered_var < raw_var * 0.5,
            "filter did not reduce variance"
        );
    }

    #[test]
    fn returns_initial_point_on_first_update() {
        let p = GeoPoint::new(36.0, 127.0);
        let mut filter = KalmanFilter::new(p);
        let out = filter.update(p, 1.0);
        assert!((out.lat - p.lat).abs() < 1e-9);
        assert!((out.lon - p.lon).abs() < 1e-9);
    }
}
