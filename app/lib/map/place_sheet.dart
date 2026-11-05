import 'package:flutter/material.dart';
import 'package:mukmuk_app/format.dart';
import 'package:mukmuk_app/map/tapped_place.dart';

/// 장소 시트에서 고른 동작.
enum PlaceAction { goHere, setOrigin }

/// 탭한 지점 정보를 보여주고 동작을 고르게 한다. 닫으면 null.
Future<PlaceAction?> showPlaceSheet(BuildContext context, TappedPlace place) {
  return showModalBottomSheet<PlaceAction>(
    context: context,
    showDragHandle: true,
    builder: (_) => PlaceSheet(place: place),
  );
}

class PlaceSheet extends StatelessWidget {
  const PlaceSheet({super.key, required this.place});

  final TappedPlace place;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final details = [
      if (place.nearbyDistanceM != null)
        '${formatDistanceM(place.nearbyDistanceM!)} 거리',
      if (place.category.isNotEmpty) place.category,
      if (place.addr != null) place.addr!,
    ].join(' · ');
    final coords =
        '${place.point.lat.toStringAsFixed(5)}, ${place.point.lon.toStringAsFixed(5)}';

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(place.name, style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(details.isEmpty ? '주변 장소 없음' : details),
            Text(coords, style: theme.textTheme.bodySmall),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => Navigator.of(context).pop(PlaceAction.goHere),
              icon: const Icon(Icons.directions),
              label: const Text('여기로 가기'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () =>
                  Navigator.of(context).pop(PlaceAction.setOrigin),
              icon: const Icon(Icons.trip_origin),
              label: const Text('출발지로 설정'),
            ),
          ],
        ),
      ),
    );
  }
}
