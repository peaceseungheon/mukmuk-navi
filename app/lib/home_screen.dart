import 'dart:async';

import 'package:flutter/material.dart' hide Route;
import 'package:maplibre_gl/maplibre_gl.dart' show LatLng;
import 'package:mukmuk_app/app_services.dart';
import 'package:mukmuk_app/attribution_dialog.dart';
import 'package:mukmuk_app/engine/engine_error_text.dart';
import 'package:mukmuk_app/ffibindings/api/types.dart';
import 'package:mukmuk_app/map/mbtiles_style.dart';
import 'package:mukmuk_app/map/navi_map.dart';
import 'package:mukmuk_app/map/place_sheet.dart';
import 'package:mukmuk_app/map/tapped_place.dart';
import 'package:mukmuk_app/nav/navigation_screen.dart';
import 'package:mukmuk_app/packs/pack_update_banner.dart';
import 'package:mukmuk_app/search/search_screen.dart';
import 'package:mukmuk_app/tts/tts_install_banner.dart';

/// 오프라인 지도 + 목적지 검색 진입점.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.services});

  final AppServices services;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final Widget _map = NaviMap(
    styleString: buildMbtilesStyle(
      '${widget.services.packDir}/map/korea.mbtiles',
    ),
    route: widget.services.nav.route,
    position: widget.services.nav.position,
    tapMarker: _tapMarker,
    onMapTap: _onMapTap,
  );
  bool _planning = false;
  final ValueNotifier<GeoPoint?> _tapMarker = ValueNotifier(null);

  AppServices get _s => widget.services;

  @override
  void initState() {
    super.initState();
    _s.gpsNotice.addListener(_onGpsNotice);
    WidgetsBinding.instance.addPostFrameCallback((_) => _onGpsNotice());
    _s.packUpdate?.check();
  }

  @override
  void dispose() {
    _s.gpsNotice.removeListener(_onGpsNotice);
    _tapMarker.dispose();
    super.dispose();
  }

  /// 지도 탭: 탭 지점에 마커를 두고 주변 장소를 찾아 시트로 보여준다.
  Future<void> _onMapTap(LatLng at) async {
    if (_planning) return;
    final tap = GeoPoint(lat: at.latitude, lon: at.longitude);
    _tapMarker.value = tap;
    try {
      final place = await resolveTappedPlace(_s.engine, tap);
      if (!mounted) return;
      final action = await showPlaceSheet(context, place);
      if (!mounted || action == null) return;
      switch (action) {
        case PlaceAction.goHere:
          await _planTo(place.toPoi());
        case PlaceAction.setOrigin:
          _s.pickedOrigin.value = place.point;
          _showMessage('출발지를 지정했습니다.');
      }
    } catch (e) {
      if (mounted) _showMessage(engineErrorText(e));
    } finally {
      if (mounted) _tapMarker.value = null;
    }
  }

  void _onGpsNotice() {
    final text = _s.gpsNotice.value;
    if (text == null || !mounted) return;
    _s.gpsNotice.value = null;
    _showMessage(text);
  }

  Future<void> _openSearch() async {
    final poi = await Navigator.of(context).push<PoiResult>(
      MaterialPageRoute(builder: (_) => SearchScreen(services: _s)),
    );
    if (poi == null || !mounted) return;
    await _planTo(poi);
  }

  Future<void> _planTo(PoiResult poi) async {
    setState(() => _planning = true);
    try {
      final route = await _s.engine.planRoute(
        start: _s.origin,
        end: poi.point,
        profile: TravelProfile.car,
      );
      if (!mounted) return;
      _s.nav.startRoute(route);
      setState(() => _planning = false);
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => NavigationScreen(services: _s, destination: poi),
        ),
      );
      _s.nav.clearRoute();
    } catch (e) {
      if (!mounted) return;
      _showMessage(engineErrorText(e));
    } finally {
      if (mounted) setState(() => _planning = false);
    }
  }

  void _showMessage(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(child: _map),
          Positioned(
            left: 16,
            right: 16,
            top: MediaQuery.paddingOf(context).top + 12,
            child: Material(
              elevation: 3,
              borderRadius: BorderRadius.circular(28),
              child: InkWell(
                borderRadius: BorderRadius.circular(28),
                onTap: _planning ? null : _openSearch,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 16,
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.search),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _planning ? '경로를 찾는 중...' : '목적지 검색',
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: 16,
            top: MediaQuery.paddingOf(context).top + 84,
            child: ValueListenableBuilder<GeoPoint?>(
              valueListenable: _s.pickedOrigin,
              builder: (context, origin, _) {
                if (origin == null) return const SizedBox.shrink();
                return InputChip(
                  avatar: const Icon(Icons.trip_origin, size: 18),
                  label: const Text('출발: 지정한 위치'),
                  onDeleted: () => _s.pickedOrigin.value = null,
                  deleteButtonTooltipMessage: '현재 위치로 출발',
                );
              },
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            top: MediaQuery.paddingOf(context).top + 132,
            child: TtsInstallBanner(ttsAvailable: _s.ttsAvailable),
          ),
          if (_s.packUpdate case final pu?)
            Positioned(
              left: 16,
              right: 16,
              bottom: 44,
              child: PackUpdateBanner(controller: pu),
            ),
          Positioned(
            left: 16,
            bottom: 16,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => AttributionDialog.show(context),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  '데이터 ${_s.info.packVersion} · © OpenStreetMap 기여자 · ODbL',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
