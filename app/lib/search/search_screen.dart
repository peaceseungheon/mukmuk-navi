import 'package:flutter/material.dart';
import 'package:mukmuk_app/app_services.dart';
import 'package:mukmuk_app/config.dart';
import 'package:mukmuk_app/engine/engine_error_text.dart';
import 'package:mukmuk_app/ffibindings/api/types.dart';
import 'package:mukmuk_app/format.dart';

/// 선택지는 design.md 6절 2번(기본 50km, UI에서 조절)에 따르고, "전국"을 더한다.
const List<double> kRadiusChoicesKm = [
  5,
  10,
  kDefaultSearchRadiusKm,
  kNationwideSearchRadiusKm,
];

String radiusChoiceLabel(double km) =>
    km == kNationwideSearchRadiusKm ? '전국' : '${km.round()}km';

/// 장소/주소 검색. 결과를 고르면 해당 PoiResult를 pop으로 돌려준다.
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key, required this.services});

  final AppServices services;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _input = TextEditingController();
  double _radiusKm = kDefaultSearchRadiusKm;
  List<PoiResult>? _results;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final query = _input.text.trim();
    if (query.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final results = await widget.services.engine.searchPoi(
        query: query,
        center: widget.services.origin,
        radiusKm: _radiusKm,
        limit: kSearchLimit,
      );
      if (!mounted) return;
      setState(() => _results = results);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _results = null;
        _error = engineErrorText(e);
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _setRadius(double km) {
    setState(() => _radiusKm = km);
    if (_results != null) _search();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _input,
          autofocus: true,
          textInputAction: TextInputAction.search,
          decoration: const InputDecoration(
            hintText: '장소·주소·초성 검색',
            border: InputBorder.none,
          ),
          onSubmitted: (_) => _search(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: '검색',
            onPressed: _busy ? null : _search,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Wrap(
              spacing: 8,
              children: [
                for (final km in kRadiusChoicesKm)
                  ChoiceChip(
                    label: Text(radiusChoiceLabel(km)),
                    selected: _radiusKm == km,
                    onSelected: _busy ? null : (_) => _setRadius(km),
                  ),
              ],
            ),
          ),
          if (_busy) const LinearProgressIndicator(),
          Expanded(child: _buildResults()),
        ],
      ),
    );
  }

  Widget _buildResults() {
    if (_error != null) {
      return Center(child: Text(_error!));
    }
    final results = _results;
    if (results == null) {
      return const Center(child: Text('검색어를 입력하세요.'));
    }
    if (results.isEmpty) {
      return const Center(child: Text('반경 안에 결과가 없습니다.'));
    }
    return ListView.builder(
      itemCount: results.length,
      itemBuilder: (context, i) {
        final poi = results[i];
        return ListTile(
          title: Text(poi.name),
          subtitle: Text(
            [poi.category, if (poi.addr != null) poi.addr!].join(' · '),
          ),
          trailing: Text(formatDistanceM(poi.distanceM)),
          onTap: () => Navigator.of(context).pop(poi),
        );
      },
    );
  }
}
