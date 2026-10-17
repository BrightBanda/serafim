/// The version of the app that is installed.
class AppVersion {
  const AppVersion({required this.name, required this.code});

  final String name;

  /// Android versionCode: the only thing compared.
  final int code;
}

/// An Android release that can be installed over this one.
class AppUpdate {
  const AppUpdate({
    required this.versionName,
    required this.versionCode,
    required this.apkUrl,
    required this.sizeBytes,
    this.sha256,
    this.changelog = '',
    this.mandatory = false,
    this.publishedAt,
  });

  final String versionName;
  final int versionCode;
  final String changelog;
  final String apkUrl;

  /// Lowercase hex. Null only for a release found on GitHub that didn't
  /// publish a digest; such an update can't be installed in-app.
  final String? sha256;
  final int sizeBytes;
  final bool mandatory;
  final DateTime? publishedAt;

  bool get canVerify => sha256 != null && sha256!.length == 64;

  /// The release page, for opening in the browser when something is wrong.
  String get releasePage {
    final i = apkUrl.indexOf('/releases/download/');
    return i < 0 ? apkUrl : '${apkUrl.substring(0, i)}/releases/latest';
  }

  bool isNewerThan(AppVersion installed) => versionCode > installed.code;

  AppUpdate copyWith({bool? mandatory, String? sha256}) => AppUpdate(
    versionName: versionName,
    versionCode: versionCode,
    changelog: changelog,
    apkUrl: apkUrl,
    sha256: sha256 ?? this.sha256,
    sizeBytes: sizeBytes,
    mandatory: mandatory ?? this.mandatory,
    publishedAt: publishedAt,
  );

  Map<String, dynamic> toJson() => {
    'version_name': versionName,
    'version_code': versionCode,
    'changelog': changelog,
    'apk_url': apkUrl,
    'sha256': sha256,
    'size_bytes': sizeBytes,
    'mandatory': mandatory,
    if (publishedAt != null) 'created_at': publishedAt!.toIso8601String(),
  };

  static AppUpdate? tryParse(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    try {
      return AppUpdate(
        versionName: json['version_name'] as String,
        versionCode: (json['version_code'] as num).toInt(),
        changelog: json['changelog'] as String? ?? '',
        apkUrl: json['apk_url'] as String,
        sha256: normaliseSha256(json['sha256'] as String?),
        sizeBytes: (json['size_bytes'] as num?)?.toInt() ?? 0,
        mandatory: json['mandatory'] as bool? ?? false,
        publishedAt: json['created_at'] is String
            ? DateTime.tryParse(json['created_at'] as String)?.toUtc()
            : null,
      );
    } catch (_) {
      return null;
    }
  }
}

/// "sha256:ABC…" or "abc…" → "abc…", or null when it isn't a SHA-256.
String? normaliseSha256(String? raw) {
  if (raw == null) return null;
  final v = raw.trim().toLowerCase().replaceFirst('sha256:', '');
  return RegExp(r'^[0-9a-f]{64}$').hasMatch(v) ? v : null;
}

/// Release tags are `v<versionName>+<versionCode>`, e.g. `v1.2.0+5` (the
/// same as pubspec's `version:`). Returns null for anything else.
({String name, int code})? parseReleaseTag(String tag) {
  final m = RegExp(r'^v?(\d+\.\d+\.\d+)\+(\d+)$').firstMatch(tag.trim());
  if (m == null) return null;
  return (name: m.group(1)!, code: int.parse(m.group(2)!));
}

/// Hosts GitHub redirects release downloads to.
const githubAssetHosts = {
  'objects.githubusercontent.com',
  'release-assets.githubusercontent.com',
};

/// Whether the app may download from [uri]: the first request must be one of
/// [repo]'s release downloads on github.com; redirects may only go to
/// GitHub's own asset hosts. Always https.
bool isAllowedDownloadUrl(Uri uri, String repo, {bool redirect = false}) {
  if (uri.scheme != 'https' || uri.userInfo.isNotEmpty) return false;
  if (uri.hasPort && uri.port != 443) return false;
  if (redirect && githubAssetHosts.contains(uri.host)) return true;
  if (uri.host != 'github.com') return false;
  final prefix = '/$repo/releases/download/';
  final path = uri.path;
  return path.startsWith(prefix) &&
      !path.contains('..') &&
      // GitHub itself may redirect once within the repo's releases.
      (redirect || path.toLowerCase().endsWith('.apk'));
}

/// 24.5 MB, 812 KB.
String formatBytes(int bytes) {
  if (bytes >= 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  if (bytes >= 1024) return '${(bytes / 1024).round()} KB';
  return '$bytes B';
}
