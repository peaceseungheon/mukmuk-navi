//! `manifest.json` 파싱·팩 검증 (`docs/agent/design.md` 3.1절).

use std::collections::BTreeMap;
use std::path::Path;

use serde::{Deserialize, Serialize};

use crate::error::EngineError;

pub const FORMAT_VERSION: u32 = 1;
pub const MANIFEST_FILE: &str = "manifest.json";

/// manifest에 반드시 있어야 하고 팩 디렉터리에 실제로 존재해야 하는 파일.
pub const REQUIRED_FILES: [&str; 3] = [
    "map/korea.mbtiles",
    "graph/korea.graph.bin",
    "poi/korea.poi.sqlite",
];

#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct FileEntry {
    #[serde(default)]
    pub size: u64,
    #[serde(default)]
    pub sha256: String,
}

#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct Manifest {
    pub format_version: u32,
    pub pack_version: String,
    pub osm_date: String,
    #[serde(default)]
    pub ngii: bool,
    pub files: BTreeMap<String, FileEntry>,
    #[serde(default)]
    pub built_at: String,
}

impl Manifest {
    /// 팩 디렉터리의 `manifest.json`을 읽는다.
    pub fn load(pack_dir: &Path) -> Result<Self, EngineError> {
        if !pack_dir.is_dir() {
            return Err(EngineError::PackNotFound);
        }
        let path = pack_dir.join(MANIFEST_FILE);
        let raw = std::fs::read(&path).map_err(|e| match e.kind() {
            std::io::ErrorKind::NotFound => EngineError::PackNotFound,
            _ => EngineError::Internal(format!("read {}: {e}", path.display())),
        })?;
        let manifest: Manifest = serde_json::from_slice(&raw)
            .map_err(|e| EngineError::FormatMismatch(format!("manifest.json: {e}")))?;
        manifest.validate(pack_dir)?;
        Ok(manifest)
    }

    /// 포맷 버전과 필수 파일 존재 여부를 검사한다.
    pub fn validate(&self, pack_dir: &Path) -> Result<(), EngineError> {
        if self.format_version != FORMAT_VERSION {
            return Err(EngineError::FormatMismatch(format!(
                "format_version {} (supported: {FORMAT_VERSION})",
                self.format_version
            )));
        }
        for name in REQUIRED_FILES {
            let Some(entry) = self.files.get(name) else {
                return Err(EngineError::FormatMismatch(format!(
                    "manifest is missing required file entry {name}"
                )));
            };
            let path = pack_dir.join(name);
            let meta = std::fs::metadata(&path).map_err(|e| match e.kind() {
                std::io::ErrorKind::NotFound => EngineError::PackNotFound,
                _ => EngineError::Internal(format!("stat {}: {e}", path.display())),
            })?;
            // 크기 0은 "아직 미기재"로 본다(파이프라인 중간 산출물 허용).
            if entry.size > 0 && meta.len() != entry.size {
                return Err(EngineError::FormatMismatch(format!(
                    "{name}: size {} != manifest {}",
                    meta.len(),
                    entry.size
                )));
            }
        }
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::PathBuf;

    fn pack(files: &[&str], version: u32) -> (tempfile::TempDir, PathBuf, Manifest) {
        let dir = tempfile::tempdir().expect("tempdir");
        for f in files {
            let p = dir.path().join(f);
            std::fs::create_dir_all(p.parent().expect("parent")).expect("mkdir");
            std::fs::write(&p, b"x").expect("write");
        }
        let mut entries = BTreeMap::new();
        for f in REQUIRED_FILES {
            entries.insert(
                f.to_string(),
                FileEntry {
                    size: 0,
                    sha256: String::new(),
                },
            );
        }
        let m = Manifest {
            format_version: version,
            pack_version: "2026.11".into(),
            osm_date: "2026-10-28".into(),
            ngii: false,
            files: entries,
            built_at: String::new(),
        };
        let path = dir.path().to_path_buf();
        (dir, path, m)
    }

    #[test]
    fn accepts_valid_pack() {
        let (_d, path, m) = pack(&REQUIRED_FILES, FORMAT_VERSION);
        m.validate(&path).expect("valid");
    }

    #[test]
    fn rejects_format_version_mismatch() {
        let (_d, path, m) = pack(&REQUIRED_FILES, 2);
        assert!(matches!(
            m.validate(&path),
            Err(EngineError::FormatMismatch(_))
        ));
    }

    #[test]
    fn rejects_missing_file_on_disk() {
        let dir = tempfile::tempdir().expect("tempdir");
        let m = Manifest {
            format_version: 1,
            pack_version: "p".into(),
            osm_date: "d".into(),
            ngii: false,
            files: REQUIRED_FILES
                .iter()
                .map(|f| {
                    (
                        f.to_string(),
                        FileEntry {
                            size: 0,
                            sha256: String::new(),
                        },
                    )
                })
                .collect(),
            built_at: String::new(),
        };
        assert!(matches!(
            m.validate(dir.path()),
            Err(EngineError::PackNotFound)
        ));
    }

    #[test]
    fn load_reports_pack_not_found() {
        let dir = tempfile::tempdir().expect("tempdir");
        assert!(matches!(
            Manifest::load(dir.path()),
            Err(EngineError::PackNotFound)
        ));
    }

    #[test]
    fn load_rejects_bad_json() {
        let dir = tempfile::tempdir().expect("tempdir");
        std::fs::write(dir.path().join(MANIFEST_FILE), b"{ not json").expect("write");
        assert!(matches!(
            Manifest::load(dir.path()),
            Err(EngineError::FormatMismatch(_))
        ));
    }
}
