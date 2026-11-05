import 'dart:async';

import 'package:flutter/material.dart' hide Route;
import 'package:mukmuk_app/app_services.dart';
import 'package:mukmuk_app/ffibindings/api/types.dart';
import 'package:mukmuk_app/format.dart';
import 'package:mukmuk_app/map/mbtiles_style.dart';
import 'package:mukmuk_app/map/navi_map.dart';
import 'package:mukmuk_app/nav/maneuver_labels.dart';
import 'package:mukmuk_app/nav/navigation_controller.dart';
import 'package:mukmuk_app/nav/position_source.dart';
import 'package:mukmuk_app/tts/instruction_text.dart';

/// 길 안내 화면. 지도는 한 번만 만들고, 안내 패널·이탈 배너만 ValueListenableBuilder로 갱신한다.
class NavigationScreen extends StatefulWidget {
  const NavigationScreen({
    super.key,
    required this.services,
    required this.destination,
  });

  final AppServices services;
  final PoiResult destination;

  @override
  State<NavigationScreen> createState() => _NavigationScreenState();
}

class _NavigationScreenState extends State<NavigationScreen> {
  late final Widget _map = NaviMap(
    styleString: buildMbtilesStyle('${widget.services.packDir}/map/korea.mbtiles'),
    route: _nav.route,
    position: _nav.position,
    followPosition: true,
    tapMarker: _noTapMarker,
  );

  /// 주행 화면은 지도 탭을 쓰지 않으므로 항상 null인 마커를 준다.
  static final ValueNotifier<GeoPoint?> _noTapMarker = ValueNotifier(null);
  StreamSubscription<RawFix>? _fixSub;
  bool _simulate = false;

  NavigationController get _nav => widget.services.nav;

  @override
  void initState() {
    super.initState();
    _nav.notice.addListener(_onNotice);
    _startFixes();
    if (!widget.services.ttsAvailable) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showMessage('오프라인 한국어 음성이 없어 음성 안내는 생략됩니다.');
      });
    }
  }

  @override
  void dispose() {
    _nav.notice.removeListener(_onNotice);
    unawaited(_fixSub?.cancel());
    super.dispose();
  }

  /// 위치 공급원(실 GPS 또는 모의 주행)을 바꿔 구독한다.
  void _startFixes() {
    final route = _nav.route.value;
    if (route == null) return;
    unawaited(_fixSub?.cancel());
    final PositionSource source = _simulate
        ? SimulatedPositionSource(route.polyline)
        : const GeolocatorPositionSource();
    _fixSub = listenFixes(
      source.fixes,
      _nav.onFix,
      (text) => _nav.notice.value = text,
    );
  }

  void _toggleSimulation() {
    setState(() => _simulate = !_simulate);
    _startFixes();
  }

  void _onNotice() {
    final message = _nav.notice.value;
    if (message == null || !mounted) return;
    _nav.notice.value = null;
    _showMessage(message);
  }

  void _showMessage(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.destination.name),
        actions: [
          IconButton(
            icon: Icon(_simulate ? Icons.gps_off : Icons.gps_fixed),
            tooltip: _simulate ? '실제 GPS 사용' : '모의 주행',
            onPressed: _toggleSimulation,
          ),
        ],
      ),
      body: Stack(
        children: [
          Positioned.fill(child: _map),
          Positioned(
            left: 12,
            right: 12,
            top: 12,
            child: Column(
              children: [
                _InstructionCard(nav: _nav),
                ValueListenableBuilder<bool>(
                  valueListenable: _nav.offRoute,
                  builder: (context, off, _) => off
                      ? const _Banner(
                          text: '경로를 벗어났습니다. 재탐색 중...',
                          color: Color(0xFFB71C1C),
                        )
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
          Positioned(
            left: 12,
            right: 12,
            bottom: 12,
            child: _BottomBar(
              nav: _nav,
              onExit: () => Navigator.of(context).pop(),
            ),
          ),
        ],
      ),
    );
  }
}

class _InstructionCard extends StatelessWidget {
  const _InstructionCard({required this.nav});

  final NavigationController nav;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<RouteStep?>(
      valueListenable: nav.instruction,
      builder: (context, step, _) {
        final text = Theme.of(context).textTheme;
        final String title;
        final String? subtitle;
        final IconData icon;
        if (step == null) {
          title = '경로 안내 준비 중';
          subtitle = null;
          icon = Icons.navigation_outlined;
        } else {
          title = maneuverLabel(step.maneuver);
          subtitle = [
            if (step.maneuver != Maneuver.arrive)
              distanceSpeech(step.distanceM),
            if (step.roadName.isNotEmpty) step.roadName,
          ].join(' · ');
          icon = maneuverIcon(step.maneuver);
        }
        return Card(
          child: ListTile(
            leading: Icon(icon, size: 36),
            title: Text(title, style: text.titleLarge),
            subtitle: subtitle == null ? null : Text(subtitle),
          ),
        );
      },
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.nav, required this.onExit});

  final NavigationController nav;
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: ValueListenableBuilder<bool>(
                valueListenable: nav.arrived,
                builder: (context, arrived, _) => arrived
                    ? Text(
                        '목적지에 도착했습니다',
                        style: Theme.of(context).textTheme.titleMedium,
                      )
                    : _RouteSummary(nav: nav),
              ),
            ),
            TextButton(onPressed: onExit, child: const Text('안내 종료')),
          ],
        ),
      ),
    );
  }
}

class _RouteSummary extends StatelessWidget {
  const _RouteSummary({required this.nav});

  final NavigationController nav;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Route?>(
      valueListenable: nav.route,
      builder: (context, route, _) => Text(
        route == null
            ? ''
            : '${formatDistanceM(route.totalDistanceM)} · ${formatDurationS(route.totalDurationS)}',
        style: Theme.of(context).textTheme.titleMedium,
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Material(
        color: color,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Text(text, style: const TextStyle(color: Colors.white)),
        ),
      ),
    );
  }
}
