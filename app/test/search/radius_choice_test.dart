import 'package:flutter_test/flutter_test.dart';
import 'package:mukmuk_app/config.dart';
import 'package:mukmuk_app/search/search_screen.dart';

void main() {
  test('검색 반경 선택지에 전국이 포함되고 라벨이 "전국"이다', () {
    expect(kRadiusChoicesKm, contains(kNationwideSearchRadiusKm));
    expect(radiusChoiceLabel(kNationwideSearchRadiusKm), '전국');
    expect(radiusChoiceLabel(kDefaultSearchRadiusKm), '50km');
    expect(radiusChoiceLabel(5), '5km');
  });
}
