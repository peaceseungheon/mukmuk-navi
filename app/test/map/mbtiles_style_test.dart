import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mukmuk_app/map/mbtiles_style.dart';

void main() {
  final style = jsonDecode(
    buildMbtilesStyle(packDir: r'D:\packs\sample'),
  ) as Map<String, dynamic>;

  test('소스는 로컬 mbtiles를 가리키고 네트워크 URL을 쓰지 않는다', () {
    final source =
        (style['sources'] as Map<String, dynamic>)[kMbtilesSourceId]
            as Map<String, dynamic>;
    expect(source['type'], 'vector');
    expect(source['url'], 'mbtiles://D:/packs/sample/map/korea.mbtiles');
    expect(source['url'].toString(), isNot(contains('http')));
  });

  test('글꼴은 팩 안 glyphs 폴더를 file://로 가리킨다', () {
    expect(
      style['glyphs'],
      'file://D:/packs/sample/glyphs/{fontstack}/{range}.pbf',
    );
    expect(style['glyphs'].toString(), isNot(contains('http')));
  });

  test('design 3.2절 vector_layers id 6종이 모두 source-layer로 쓰인다', () {
    final layers = style['layers'] as List<dynamic>;
    final sourceLayers = {
      for (final l in layers)
        if ((l as Map)['source-layer'] != null) l['source-layer'] as String,
    };
    expect(sourceLayers, unorderedEquals(kMbtilesLayerIds));
  });

  test('line 레이어는 LineString만, fill 레이어는 Polygon만 받는다(혼합 타일 경고 방지)', () {
    for (final l in style['layers'] as List<dynamic>) {
      final type = (l as Map)['type'];
      if (type != 'line' && type != 'fill') continue;
      final want = type == 'line' ? 'LineString' : 'Polygon';
      expect(
        jsonEncode(l['filter']),
        contains(want),
        reason: l['id'] as String,
      );
    }
  });

  test('도로는 등급별 레이어로 나뉘고 선 두께가 줌에 비례한다', () {
    final roads = (style['layers'] as List<dynamic>)
        .where((l) => (l as Map)['source-layer'] == 'roads' && l['type'] == 'line')
        .toList();
    expect(roads.length, 3);
    for (final l in roads) {
      final width = (l as Map)['paint']['line-width'] as List<dynamic>;
      expect(width.first, 'interpolate');
    }
  });

  Map<String, dynamic> layerById(String id) =>
      (style['layers'] as List<dynamic>).firstWhere(
            (l) => (l as Map)['id'] == id,
          )
          as Map<String, dynamic>;

  test('도로명 라벨은 roads 선에 줌 14부터 선을 따라 그린다', () {
    final l = layerById('road_labels');
    expect(l['type'], 'symbol');
    expect(l['source-layer'], 'roads');
    expect(l['minzoom'], kRoadLabelMinZoom);
    expect(l['layout']['symbol-placement'], 'line');
    expect(l['layout']['text-font'], [kGlyphFontStack]);
    expect(jsonEncode(l['filter']), allOf(contains('LineString'), contains('name')));
  });

  test('POI 이름은 줌 14부터, 이름 있는 점에만 그린다', () {
    final l = layerById('poi_labels');
    expect(l['type'], 'symbol');
    expect(l['source-layer'], 'poi');
    expect(l['minzoom'], kPoiLabelMinZoom);
    expect(l['minzoom'] as int, greaterThan(layerById('poi')['minzoom'] as int));
    expect(jsonEncode(l['filter']), allOf(contains('Point'), contains('name:ko')));
    expect(jsonEncode(l['layout']['text-field']), allOf(contains('name'), contains('name:ko')));
  });

  test('라벨 레이어는 글꼴 스택이 스타일 glyphs 템플릿과 맞는다', () {
    expect(style['glyphs'].toString(), contains('{fontstack}/{range}.pbf'));
    expect(kGlyphFontStack, isNot(contains(' ')));
  });
}
