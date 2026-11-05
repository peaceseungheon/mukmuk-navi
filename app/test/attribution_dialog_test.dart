import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mukmuk_app/attribution_dialog.dart';

void main() {
  testWidgets('show()가 ODbL 문구와 두 URL을 보여주고 닫기로 닫힌다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => AttributionDialog.show(context),
            child: const Text('open'),
          ),
        ),
      ),
    );
    expect(find.byType(AttributionDialog), findsNothing);

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(
      find.text('https://www.openstreetmap.org/copyright'),
      findsOneWidget,
    );
    expect(
      find.text('https://opendatacommons.org/licenses/odbl/1-0/'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Open Database License(ODbL) 1.0'),
      findsOneWidget,
    );
    expect(find.textContaining('© OpenStreetMap 기여자'), findsOneWidget);
    expect(find.textContaining('파생'), findsOneWidget);

    await tester.tap(find.text('닫기'));
    await tester.pumpAndSettle();
    expect(find.byType(AttributionDialog), findsNothing);
  });
}
