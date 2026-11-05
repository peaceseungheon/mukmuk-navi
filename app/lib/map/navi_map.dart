import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' hide Route;
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:mukmuk_app/config.dart';
import 'package:mukmuk_app/ffibindings/api/types.dart';

const String _routeSourceId = 'route';
const String _routeLayerId = 'route-line';
const String _positionSourceId = 'position';
const String _positionLayerId = 'position-dot';
const String _tapSourceId = 'tap-marker';
const String _tapLayerId = 'tap-marker-dot';

const Map<String, Object> _emptyFc = {
  'type': 'FeatureCollection',
  'features': <Object>[],
};

/// 지도 위젯. 부모는 이 위젯을 리빌드하지 않는다. 경로·위치 변화는 ValueListenable로
/// 받아 MapLibre GeoJSON 소스 데이터만 갱신한다(부모 setState 없음).
class NaviMap extends StatefulWidget {
  const NaviMap({
    super.key,
    required this.styleString,
    required this.route,
    required this.position,
    this.followPosition = false,
    required this.tapMarker,
    this.onMapTap,
  });

  final String styleString;
  final ValueListenable<Route?> route;
  final ValueListenable<GeoPoint?> position;
  final bool followPosition;

  /// 사용자가 탭한 지점 표시. null이면 마커를 지운다.
  final ValueListenable<GeoPoint?> tapMarker;

  /// 지도 탭 콜백(좌표).
  final ValueChanged<LatLng>? onMapTap;

  @override
  State<NaviMap> createState() => _NaviMapState();
}

class _NaviMapState extends State<NaviMap> {
  MapLibreMapController? _controller;
  bool _styleReady = false;

  @override
  void initState() {
    super.initState();
    widget.route.addListener(_onRouteChanged);
    widget.position.addListener(_onPositionChanged);
    widget.tapMarker.addListener(_onTapMarkerChanged);
  }

  @override
  void didUpdateWidget(covariant NaviMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.route != widget.route) {
      oldWidget.route.removeListener(_onRouteChanged);
      widget.route.addListener(_onRouteChanged);
    }
    if (oldWidget.position != widget.position) {
      oldWidget.position.removeListener(_onPositionChanged);
      widget.position.addListener(_onPositionChanged);
    }
    if (oldWidget.tapMarker != widget.tapMarker) {
      oldWidget.tapMarker.removeListener(_onTapMarkerChanged);
      widget.tapMarker.addListener(_onTapMarkerChanged);
    }
  }

  @override
  void dispose() {
    widget.route.removeListener(_onRouteChanged);
    widget.position.removeListener(_onPositionChanged);
    widget.tapMarker.removeListener(_onTapMarkerChanged);
    super.dispose();
  }

  Future<void> _onStyleLoaded() async {
    final c = _controller;
    if (c == null) return;
    await c.addGeoJsonSource(_routeSourceId, _emptyFc);
    await c.addLineLayer(
      _routeSourceId,
      _routeLayerId,
      const LineLayerProperties(
        lineColor: '#1565c0',
        lineWidth: 6,
        lineCap: 'round',
        lineJoin: 'round',
      ),
    );
    await c.addGeoJsonSource(_positionSourceId, _emptyFc);
    await c.addCircleLayer(
      _positionSourceId,
      _positionLayerId,
      const CircleLayerProperties(
        circleRadius: 9,
        circleColor: '#2e7d32',
        circleStrokeColor: '#ffffff',
        circleStrokeWidth: 3,
      ),
    );
    await c.addGeoJsonSource(_tapSourceId, _emptyFc);
    await c.addCircleLayer(
      _tapSourceId,
      _tapLayerId,
      const CircleLayerProperties(
        circleRadius: 8,
        circleColor: '#e65100',
        circleStrokeColor: '#ffffff',
        circleStrokeWidth: 2,
      ),
    );
    _styleReady = true;
    // 스타일 로드 전에 쌓인 상태를 한 번 반영한다.
    _onRouteChanged();
    _onPositionChanged();
    _onTapMarkerChanged();
  }

  void _onTapMarkerChanged() {
    if (!_styleReady) return;
    final p = widget.tapMarker.value;
    _pushTapMarker(p);
  }

  Future<void> _pushTapMarker(GeoPoint? p) async {
    final c = _controller;
    if (c == null) return;
    if (p == null) {
      await c.setGeoJsonSource(_tapSourceId, _emptyFc);
      return;
    }
    await c.setGeoJsonSource(_tapSourceId, {
      'type': 'FeatureCollection',
      'features': [
        {
          'type': 'Feature',
          'properties': <String, Object>{},
          'geometry': {
            'type': 'Point',
            'coordinates': [p.lon, p.lat],
          },
        },
      ],
    });
  }

  void _onRouteChanged() {
    if (!_styleReady) return;
    _pushRoute(widget.route.value);
  }

  void _onPositionChanged() {
    final pos = widget.position.value;
    if (!_styleReady || pos == null) return;
    _pushPosition(pos);
  }

  Future<void> _pushRoute(Route? route) async {
    final c = _controller;
    if (c == null) return;
    final polyline = route?.polyline ?? const <GeoPoint>[];
    if (polyline.length < 2) {
      await c.setGeoJsonSource(_routeSourceId, _emptyFc);
      return;
    }
    await c.setGeoJsonSource(_routeSourceId, {
      'type': 'FeatureCollection',
      'features': [
        {
          'type': 'Feature',
          'properties': <String, Object>{},
          'geometry': {
            'type': 'LineString',
            'coordinates': [
              for (final p in polyline) [p.lon, p.lat],
            ],
          },
        },
      ],
    });
    await c.moveCamera(
      CameraUpdate.newLatLngBounds(
        _boundsOf(polyline),
        left: 48,
        top: 48,
        right: 48,
        bottom: 160,
      ),
    );
  }

  Future<void> _pushPosition(GeoPoint p) async {
    final c = _controller;
    if (c == null) return;
    await c.setGeoJsonSource(_positionSourceId, {
      'type': 'FeatureCollection',
      'features': [
        {
          'type': 'Feature',
          'properties': <String, Object>{},
          'geometry': {
            'type': 'Point',
            'coordinates': [p.lon, p.lat],
          },
        },
      ],
    });
    if (widget.followPosition) {
      await c.moveCamera(CameraUpdate.newLatLng(LatLng(p.lat, p.lon)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return MapLibreMap(
      styleString: widget.styleString,
      initialCameraPosition: const CameraPosition(
        target: LatLng(kMapInitialLat, kMapInitialLon),
        zoom: kMapInitialZoom,
      ),
      minMaxZoomPreference: const MinMaxZoomPreference(6, 16),
      compassEnabled: false,
      attributionButtonPosition: AttributionButtonPosition.bottomRight,
      onMapCreated: (controller) => _controller = controller,
      onStyleLoadedCallback: _onStyleLoaded,
      onMapClick: (_, coordinates) => widget.onMapTap?.call(coordinates),
    );
  }
}

LatLngBounds _boundsOf(List<GeoPoint> points) {
  var minLat = points.first.lat;
  var maxLat = minLat;
  var minLon = points.first.lon;
  var maxLon = minLon;
  for (final p in points) {
    if (p.lat < minLat) minLat = p.lat;
    if (p.lat > maxLat) maxLat = p.lat;
    if (p.lon < minLon) minLon = p.lon;
    if (p.lon > maxLon) maxLon = p.lon;
  }
  return LatLngBounds(
    southwest: LatLng(minLat, minLon),
    northeast: LatLng(maxLat, maxLon),
  );
}
