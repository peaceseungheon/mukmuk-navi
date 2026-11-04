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

/// 로컬 mbtiles(MVT)를 소스로 쓰는 MapLibre 스타일 JSON. 네트워크 리소스를 참조하지 않는다.
/// [mbtilesPath]는 팩 디렉터리 기준 `map/korea.mbtiles`의 절대 경로.
String buildMbtilesStyle(String mbtilesPath) {
  final url = 'mbtiles://${mbtilesPath.replaceAll('\\', '/')}';
  final style = <String, Object>{
    'version': 8,
    'name': 'mukmuk-offline',
    'sources': {
      kMbtilesSourceId: {
        'type': 'vector',
        'url': url,
        'attribution': '© OpenStreetMap contributors',
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
    ],
  };
  return jsonEncode(style);
}

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
