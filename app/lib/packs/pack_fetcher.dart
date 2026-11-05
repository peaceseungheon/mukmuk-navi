import 'dart:io';

import 'package:http/http.dart' as http;

/// 원격 팩 접근 경계. 테스트에서는 가짜로 대체한다.
abstract interface class PackFetcher {
  Future<List<int>> fetchManifest();

  /// [relPath] 파일을 [dest]에 받는다. 받은 바이트가 [maxBytes]를 넘으면 중단한다.
  Future<void> download(
    String relPath,
    File dest,
    int maxBytes,
    void Function(int chunkBytes) onBytes,
  );
}

const _timeout = Duration(seconds: 30);
const _maxManifestBytes = 1 << 20;

class HttpPackFetcher implements PackFetcher {
  HttpPackFetcher(String baseUrl, {http.Client? client})
    : _base = Uri.parse(baseUrl.endsWith('/') ? baseUrl : '$baseUrl/'),
      _client = client ?? http.Client();

  final Uri _base;
  final http.Client _client;

  Future<http.StreamedResponse> _get(String rel) async {
    final req = http.Request('GET', _base.resolve(rel));
    final res = await _client.send(req).timeout(_timeout);
    if (res.statusCode != 200) throw HttpException('status ${res.statusCode}');
    return res;
  }

  @override
  Future<List<int>> fetchManifest() async {
    final res = await _get('manifest.json');
    final bytes = <int>[];
    await for (final c in res.stream.timeout(_timeout)) {
      bytes.addAll(c);
      if (bytes.length > _maxManifestBytes) {
        throw const HttpException('manifest too large');
      }
    }
    return bytes;
  }

  @override
  Future<void> download(
    String relPath,
    File dest,
    int maxBytes,
    void Function(int) onBytes,
  ) async {
    final res = await _get(relPath);
    await dest.parent.create(recursive: true);
    final sink = dest.openWrite();
    var total = 0;
    try {
      await for (final c in res.stream.timeout(_timeout)) {
        total += c.length;
        if (total > maxBytes) throw const HttpException('too large');
        sink.add(c);
        onBytes(c.length);
      }
    } finally {
      await sink.close();
    }
  }
}
