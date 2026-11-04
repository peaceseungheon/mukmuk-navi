import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mukmuk_app/map/mbtiles_style.dart';

void main() {
  final style = jsonDecode(
    buildMbtilesStyle(r'D:\packs\sample\map\korea.mbtiles'),
  ) as Map<String, dynamic>;

  test('소스는 로컬 mbtiles를 가리키고 네트워크 URL을 쓰지 않는다', () {
    final source =
        (style['sources'] as Map<String, dynamic>)[kMbtilesSourceId]
            as Map<String, dynamic>;
    expect(source['type'], 'vector');
    expect(source['url'], 'mbtiles://D:/packs/sample/map/korea.mbtiles');
    expect(source['url'].toString(), isNot(contains('http')));
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
        .where((l) => (l as Map)['source-layer'] == 'roads')
        .toList();
    expect(roads.length, 3);
    for (final l in roads) {
      final width = (l as Map)['paint']['line-width'] as List<dynamic>;
      expect(width.first, 'interpolate');
    }
  });
}
