import 'dart:convert';

/// 다운로드해야 하는 필수 파일(design.md 3.1절).
const List<String> kRequiredPackFiles = [
  'map/korea.mbtiles',
  'graph/korea.graph.bin',
  'poi/korea.poi.sqlite',
];

class PackFileEntry {
  const PackFileEntry({required this.size, required this.sha256});

  final int size;
  final String sha256;
}

/// 원격 manifest.json. 신뢰하지 않는 입력이므로 파싱 시점에 모두 검증한다.
class PackManifest {
  const PackManifest({required this.version, required this.files});

  final String version;
  final Map<String, PackFileEntry> files;

  int get totalBytes => files.values.fold(0, (a, f) => a + f.size);

  /// 로컬 manifest에서 pack_version만 읽는다. 없거나 깨졌으면 [FormatException].
  static String readVersion(List<int> bytes) {
    final json = _decode(bytes);
    final version = json['pack_version'];
    if (version is! String || _parseVersion(version) == null) {
      throw const FormatException('pack_version 오류');
    }
    return version;
  }

  /// 형식이 틀리면 [FormatException].
  factory PackManifest.parse(List<int> bytes) {
    final json = _decode(bytes);
    final version = readVersion(bytes);
    final rawFiles = json['files'];
    if (rawFiles is! Map<String, dynamic>) {
      throw const FormatException('files 오류');
    }
    final files = <String, PackFileEntry>{};
    for (final e in rawFiles.entries) {
      if (!isSafeRelativePath(e.key)) {
        throw const FormatException('허용되지 않는 파일 경로');
      }
      final v = e.value;
      if (v is! Map<String, dynamic>) throw const FormatException('files 오류');
      final size = v['size'];
      final sha = v['sha256'];
      if (size is! int || size < 0 || sha is! String) {
        throw const FormatException('files 항목 오류');
      }
      if (!RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(sha)) {
        throw const FormatException('sha256 형식 오류');
      }
      files[e.key] = PackFileEntry(size: size, sha256: sha.toLowerCase());
    }
    for (final r in kRequiredPackFiles) {
      if (!files.containsKey(r)) throw const FormatException('필수 파일 누락');
    }
    return PackManifest(version: version, files: files);
  }
}

Map<String, dynamic> _decode(List<int> bytes) {
  try {
    final json = jsonDecode(utf8.decode(bytes));
    if (json is Map<String, dynamic>) return json;
  } on FormatException {
    // 아래에서 같은 오류로 통일한다.
  }
  throw const FormatException('manifest 형식 오류');
}

/// 절대경로·`..`·역슬래시·드라이브 표기를 거부한다.
bool isSafeRelativePath(String path) {
  if (path.isEmpty || path.startsWith('/')) return false;
  if (path.contains(r'\') || path.contains(':') || path.contains('\u0000')) {
    return false;
  }
  return path.split('/').every((s) => s.isNotEmpty && s != '.' && s != '..');
}

List<int>? _parseVersion(String v) {
  final parts = v.split('.').map(int.tryParse).toList();
  if (parts.any((p) => p == null || p < 0)) return null;
  return parts.cast<int>();
}

/// 점으로 구분된 숫자 버전 비교("2026.11" 형식). 파싱 불가 값은 0으로 본다.
int comparePackVersion(String a, String b) {
  final x = _parseVersion(a) ?? const [0];
  final y = _parseVersion(b) ?? const [0];
  for (var i = 0; i < x.length || i < y.length; i++) {
    final c = (i < x.length ? x[i] : 0).compareTo(i < y.length ? y[i] : 0);
    if (c != 0) return c;
  }
  return 0;
}
