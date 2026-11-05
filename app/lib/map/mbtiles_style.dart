import 'dart:convert';

/// design.md 3.2절 vector_layers id 6종. 스타일은 이 id로만 레이어를 나눈다.
const List<String> kMbtilesLayerIds = [
  'roads',
  'water',
  'landuse',
  'buildings',
  'boundaries',
  'poi',
];

const String kMbtilesSourceId = 'korea';

/// 팩 안 글꼴 폴더 이름(`glyphs/<fontstack>/<range>.pbf`). 공백 없이 둬서 URL 인코딩을 피한다.
const String kGlyphFontStack = 'NotoSansKR-Regular';

/// 도로명 라벨을 켜는 최소 줌. 그 아래는 도로가 많아 과밀해진다.
const int kRoadLabelMinZoom = 14;

/// POI 이름을 켜는 최소 줌. POI 점은 z12부터 보이지만 이름은 z14부터 보인다.
const int kPoiLabelMinZoom = 14;

/// 로컬 팩의 mbtiles(MVT)와 글꼴(glyph PBF)을 소스로 쓰는 MapLibre 스타일 JSON.
/// 네트워크 리소스를 참조하지 않는다. [packDir]는 `map/`, `glyphs/`가 놓인 팩 디렉터리 절대 경로.
String buildMbtilesStyle({required String packDir}) {
  final base = packDir.replaceAll('\\', '/');
  final style = <String, Object>{
    'version': 8,
    'name': 'mukmuk-offline',
    'glyphs': 'file://$base/glyphs/{fontstack}/{range}.pbf',
    'sources': {
      kMbtilesSourceId: {
        'type': 'vector',
        'url': 'mbtiles://$base/map/korea.mbtiles',
        'attribution': '© OpenStreetMap 기여자 · ODbL',
      },
    },
    'layers': [
      {
        'id': 'background',
        'type': 'background',
        'paint': {'background-color': '#f2efe9'},
      },
      _fill('landuse', '#e4ecd4'),
      _fill('water', '#a8d4f0'),
      _fill('buildings', '#d9d0c9'),
      _line('boundaries', 'boundaries', '#9e9e9e', _widthAt(0.4, 0.8)),
      ..._roadLayers(),
      {
        'id': 'poi',
        'type': 'circle',
        'source': kMbtilesSourceId,
        'source-layer': 'poi',
        'minzoom': 12,
        'paint': {'circle-radius': 3, 'circle-color': '#e65100'},
      },
      _roadLabel(),
      _poiLabel(),
    ],
  };
  return jsonEncode(style);
}

/// 이름 표시 식. 한국 OSM은 `name`이 한글인 경우가 대부분이라 `name`을 먼저 본다.
const List<Object> _nameExpr = [
  'coalesce',
  ['get', 'name'],
  ['get', 'name:ko'],
];

/// 도로명: 선을 따라 그린다. 라벨 충돌은 MapLibre가 자동으로 피한다.
Map<String, Object> _roadLabel() => {
  'id': 'road_labels',
  'type': 'symbol',
  'source': kMbtilesSourceId,
  'source-layer': 'roads',
  'minzoom': kRoadLabelMinZoom,
  'filter': [
    'all',
    _geom('LineString'),
    ['has', 'name'],
  ],
  'layout': {
    'symbol-placement': 'line',
    'text-field': ['get', 'name'],
    'text-font': [kGlyphFontStack],
    'text-size': 11,
  },
  'paint': {
    'text-color': '#4a4a4a',
    'text-halo-color': '#ffffff',
    'text-halo-width': 1.5,
  },
};

/// POI 이름: 점 아래에 둔다. 이름이 없는 점은 그리지 않는다.
Map<String, Object> _poiLabel() => {
  'id': 'poi_labels',
  'type': 'symbol',
  'source': kMbtilesSourceId,
  'source-layer': 'poi',
  'minzoom': kPoiLabelMinZoom,
  'filter': [
    'all',
    _geom('Point'),
    [
      'any',
      ['has', 'name'],
      ['has', 'name:ko'],
    ],
  ],
  'layout': {
    'text-field': _nameExpr,
    'text-font': [kGlyphFontStack],
    'text-size': 11,
    'text-anchor': 'top',
    'text-offset': [0, 0.8],
    'text-max-width': 8,
  },
  'paint': {
    'text-color': '#3e2723',
    'text-halo-color': '#ffffff',
    'text-halo-width': 1.5,
  },
};

/// 타일의 한 source-layer에 점·선·면이 섞여 있어(OSM 원본) 스타일 레이어 종류에 맞는
/// 지오메트리만 통과시킨다. 안 그러면 line 레이어가 점/면을 받아 경고가 난다.
List<Object> _geom(String type) => [
  '==',
  ['geometry-type'],
  type,
];

List<Object> _widthAt(double lo, double hi, {int z0 = 6, int z1 = 14}) => [
  'interpolate',
  ['exponential', 1.5],
  ['zoom'],
  z0,
  lo,
  z1,
  hi,
];

Map<String, Object> _fill(String sourceLayer, String color) => {
  'id': sourceLayer,
  'type': 'fill',
  'source': kMbtilesSourceId,
  'source-layer': sourceLayer,
  'filter': _geom('Polygon'),
  'paint': {'fill-color': color, 'fill-opacity': 0.9},
};

Map<String, Object> _line(
  String id,
  String sourceLayer,
  String color,
  Object width, {
  Object? filter,
  int minzoom = 0,
}) => {
  'id': id,
  'type': 'line',
  'source': kMbtilesSourceId,
  'source-layer': sourceLayer,
  'minzoom': minzoom,
  'filter': ['all', _geom('LineString'), ?filter],
  'layout': {'line-cap': 'round', 'line-join': 'round'},
  'paint': {'line-color': color, 'line-width': width},
};

List<Object> _highwayIn(List<String> classes) => [
  'in',
  ['get', 'highway'],
  ['literal', classes],
];

/// 도로 등급별 3단: 보행로(z14~) < 이면도로(z12~) < 간선(z6~). 등급이 없으면 그리지 않는다.
List<Map<String, Object>> _roadLayers() => [
  _line(
    'roads_path',
    'roads',
    '#c9bfb4',
    _widthAt(0.3, 1.2),
    minzoom: 14,
    filter: _highwayIn([
      'footway',
      'path',
      'steps',
      'cycleway',
      'pedestrian',
      'track',
    ]),
  ),
  _line(
    'roads_minor',
    'roads',
    '#ffffff',
    _widthAt(0.3, 4),
    minzoom: 12,
    filter: _highwayIn([
      'residential',
      'unclassified',
      'living_street',
      'service',
      'tertiary',
      'tertiary_link',
    ]),
  ),
  _line(
    'roads_major',
    'roads',
    '#f5b95f',
    _widthAt(0.8, 7),
    filter: _highwayIn([
      'motorway',
      'motorway_link',
      'trunk',
      'trunk_link',
      'primary',
      'primary_link',
      'secondary',
      'secondary_link',
    ]),
  ),
];
