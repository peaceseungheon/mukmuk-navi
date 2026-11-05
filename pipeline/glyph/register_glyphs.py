"""글꼴 PBF(glyphs/<fontstack>/<range>.pbf)를 팩 manifest.json의 files 목록에 등록한다.

글꼴 생성(1회): build_pbf_glyphs <글꼴 폴더> <출력 폴더>
  - 입력: data/work/glyph/NotoSansKR-Regular.otf (Noto Sans KR, SIL OFL 1.1)
  - 출력: <출력 폴더>/NotoSansKR-Regular/<range>.pbf (글꼴 스택 이름 = 파일명)
  - 생성된 PBF를 팩의 glyphs/NotoSansKR-Regular/ 아래에 복사한 뒤 아래 명령으로 등록한다.

사용: python register_glyphs.py <팩 디렉터리> <fontstack 이름>
- 각 PBF의 size와 sha256을 계산해 `glyphs/<fontstack>/<range>.pbf` 키로 넣는다.
- 기존 files 항목(map/graph/poi)은 건드리지 않는다. 같은 키가 있으면 갱신한다.
- 글꼴 PBF 자체는 data/ 아래 생성물이며 저장소에 넣지 않는다.
"""

import hashlib
import json
import sys
from pathlib import Path


def sha256_of(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def main(argv: list[str]) -> int:
    if len(argv) != 3:
        print(__doc__)
        return 2
    pack = Path(argv[1])
    stack = argv[2]
    if "/" in stack or "\\" in stack or stack in ("", ".", ".."):
        print("fontstack 이름 오류")
        return 2
    glyph_dir = pack / "glyphs" / stack
    pbfs = sorted(glyph_dir.glob("*.pbf"))
    if not pbfs:
        print(f"PBF 없음: {glyph_dir}")
        return 1

    manifest_path = pack / "manifest.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    files = manifest["files"]
    for p in pbfs:
        key = f"glyphs/{stack}/{p.name}"
        files[key] = {"size": p.stat().st_size, "sha256": sha256_of(p)}

    manifest_path.write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    total = sum(files[f"glyphs/{stack}/{p.name}"]["size"] for p in pbfs)
    print(f"등록 {len(pbfs)}개, {total} bytes -> {manifest_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
