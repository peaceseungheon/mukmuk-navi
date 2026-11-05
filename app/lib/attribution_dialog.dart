import 'package:flutter/material.dart';

const osmCopyrightUrl = 'https://www.openstreetmap.org/copyright';
const odblUrl = 'https://opendatacommons.org/licenses/odbl/1-0/';
const oflUrl = 'https://openfontlicense.org';

/// ODbL 4.3 / OSM 가이드 출처 표기. 링크 패키지 없이 전체 URL을 텍스트로 보인다.
class AttributionDialog extends StatelessWidget {
  const AttributionDialog({super.key});

  static Future<void> show(BuildContext context) => showDialog<void>(
    context: context,
    builder: (_) => const AttributionDialog(),
  );

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('출처 정보'),
      content: const SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SelectableText('지도 데이터 © OpenStreetMap 기여자 (OpenStreetMap)'),
            SelectableText(osmCopyrightUrl),
            SizedBox(height: 12),
            SelectableText('이 데이터는 Open Database License(ODbL) 1.0으로 제공됩니다.'),
            SelectableText(odblUrl),
            SizedBox(height: 12),
            Text('데이터 팩은 OpenStreetMap 데이터에서 파생되었습니다.'),
            SizedBox(height: 12),
            SelectableText('지도 글꼴: Noto Sans KR © Google, SIL Open Font License 1.1'),
            SelectableText(oflUrl),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('닫기'),
        ),
      ],
    );
  }
}
