import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:serafim/src/data/models/app_update.dart';

/// Why an update couldn't be downloaded or installed.
enum UpdateErrorKind {
  offline,
  interrupted,
  storage,
  badUrl,
  hashMismatch,
  wrongApp,
  wrongSigner,
  notNewer,
  incompatible,
  permissionDenied,
  installerCancelled,
  installFailed,
  cancelled,
  unverifiable,
  unknown,
}

class UpdateFailure implements Exception {
  const UpdateFailure(this.kind, this.message);

  final UpdateErrorKind kind;
  final String message;

  /// Whether trying again could help.
  bool get retryable => switch (kind) {
    UpdateErrorKind.offline ||
    UpdateErrorKind.interrupted ||
    UpdateErrorKind.storage ||
    UpdateErrorKind.permissionDenied ||
    UpdateErrorKind.installerCancelled ||
    UpdateErrorKind.installFailed ||
    UpdateErrorKind.cancelled ||
    UpdateErrorKind.unknown => true,
    _ => false,
  };

  @override
  String toString() => 'UpdateFailure($kind): $message';
}

/// What the server knows about releases (`GET /app/latest-update`).
class ServerUpdateInfo {
  const ServerUpdateInfo({this.latest, this.minVersionCode = 0});

  final AppUpdate? latest;

  /// Versions below this must update before using the app.
  final int minVersionCode;
}

/// A release found on GitHub, with the ETag to ask cheaply next time.
class GitHubRelease {
  const GitHubRelease({required this.update, this.etag});

  final AppUpdate update;
  final String? etag;
}

/// Finding releases: the Serafim server (announcements, mandatory minimum)
/// and GitHub's public releases API. Neither call sends credentials to
/// GitHub.
class UpdateService {
  UpdateService({required this.api, required this.github, required this.repo});

  /// The Serafim backend.
  final Dio api;

  /// A plain client for GitHub: no auth interceptor, no tokens.
  final Dio github;
  final String repo;

  Future<ServerUpdateInfo> serverInfo() async {
    final r = await api.get<dynamic>('/app/latest-update');
    final data = r.data;
    if (data is! Map<String, dynamic>) return const ServerUpdateInfo();
    return ServerUpdateInfo(
      latest: AppUpdate.tryParse(data['latest']),
      minVersionCode: (data['min_version_code'] as num?)?.toInt() ?? 0,
    );
  }

  /// The latest GitHub release, or null if there is none usable. With
  /// [etag], an unchanged release costs nothing (304, not counted against the
  /// rate limit) and returns [unchanged].
  Future<({GitHubRelease? release, bool unchanged})> latestRelease({
    String? etag,
  }) async {
    final r = await github.get<dynamic>(
      'https://api.github.com/repos/$repo/releases/latest',
      options: Options(
        headers: {
          'accept': 'application/vnd.github+json',
          'x-github-api-version': '2022-11-28',
          if (etag != null) 'if-none-match': etag,
        },
        validateStatus: (s) => s == 200 || s == 304 || s == 404,
      ),
    );
    if (r.statusCode == 304) return (release: null, unchanged: true);
    if (r.statusCode == 404) return (release: null, unchanged: false);
    final data = r.data;
    if (data is! Map<String, dynamic>) return (release: null, unchanged: false);
    final tag = parseReleaseTag(data['tag_name'] as String? ?? '');
    if (tag == null || data['draft'] == true || data['prerelease'] == true) {
      return (release: null, unchanged: false);
    }
    // Every .apk on the release; per-CPU builds are named …-<abi>.apk.
    final apks = <Map<String, dynamic>>[];
    for (final a in (data['assets'] as List? ?? const [])) {
      if (a is! Map<String, dynamic>) continue;
      final name = (a['name'] as String? ?? '').toLowerCase();
      final link = a['browser_download_url'] as String?;
      if (name.endsWith('.apk') &&
          link != null &&
          isAllowedDownloadUrl(Uri.parse(link), repo)) {
        apks.add(a);
      }
    }
    if (apks.isEmpty) return (release: null, unchanged: false);
    final variants = [
      for (final a in apks)
        if (abiFromFileName(a['name'] as String) case final abi?)
          ApkVariant(
            abi: abi,
            apkUrl: a['browser_download_url'] as String,
            sha256: normaliseSha256(a['digest'] as String?),
            sizeBytes: (a['size'] as num?)?.toInt() ?? 0,
          ),
    ];
    // The top-level build is the arm64 one when there is one.
    final apk = apks.firstWhere(
      (a) => abiFromFileName(a['name'] as String) == 'arm64-v8a',
      orElse: () => apks.first,
    );
    final url = apk['browser_download_url'] as String;
    return (
      release: GitHubRelease(
        update: AppUpdate(
          versionName: tag.name,
          versionCode: tag.code,
          changelog: (data['body'] as String? ?? '').trim(),
          apkUrl: url,
          // GitHub publishes a SHA-256 digest for release assets.
          sha256: normaliseSha256(apk['digest'] as String?),
          sizeBytes: (apk['size'] as num?)?.toInt() ?? 0,
          publishedAt: DateTime.tryParse(
            data['published_at'] as String? ?? '',
          )?.toUtc(),
          variants: variants,
        ),
        etag: r.headers.value('etag'),
      ),
      unchanged: false,
    );
  }
}

/// Downloads an APK from GitHub releases: every hop is checked against the
/// allow-list (redirects are followed by hand), interrupted downloads resume
/// with a Range request, and nothing is ever sent but the request itself.
class ApkDownloader {
  ApkDownloader({required this.dio, required this.repo});

  /// A plain client: no auth interceptor, so no token ever goes to GitHub.
  final Dio dio;
  final String repo;

  static const _maxRedirects = 5;

  Future<void> download(
    Uri url,
    File target, {
    required void Function(int received, int total) onProgress,
    CancelToken? cancel,
  }) async {
    var current = url;
    for (var hop = 0; hop <= _maxRedirects; hop++) {
      if (!isAllowedDownloadUrl(current, repo, redirect: hop > 0)) {
        throw const UpdateFailure(
          UpdateErrorKind.badUrl,
          "This update doesn't come from Serafim's GitHub releases, so it "
          "won't be downloaded.",
        );
      }
      final existing = await target.exists() ? await target.length() : 0;
      Response<ResponseBody> response;
      try {
        response = await dio.getUri<ResponseBody>(
          current,
          cancelToken: cancel,
          options: Options(
            responseType: ResponseType.stream,
            followRedirects: false,
            validateStatus: (s) => s != null && (s < 400 || s == 416),
            headers: {if (existing > 0) 'range': 'bytes=$existing-'},
          ),
        );
      } on DioException catch (e) {
        throw _failure(e);
      }
      final status = response.statusCode ?? 0;

      if (status >= 300 && status < 400) {
        final location = response.headers.value('location');
        if (location == null) break;
        current = current.resolve(location);
        continue;
      }
      if (status == 416) {
        // We already have everything (the range starts at the end).
        onProgress(existing, existing);
        return;
      }
      final body = response.data;
      if (body == null || status < 200 || status >= 300) break;

      final append = status == 206 && existing > 0;
      final length = body.contentLength;
      final total = length < 0 ? -1 : (append ? existing + length : length);
      var received = append ? existing : 0;
      final sink = target.openWrite(
        mode: append ? FileMode.append : FileMode.write,
      );
      try {
        await for (final Uint8List chunk in body.stream) {
          sink.add(chunk);
          received += chunk.length;
          onProgress(received, total);
        }
        await sink.flush();
      } on DioException catch (e) {
        throw _failure(e);
      } on FileSystemException catch (e) {
        throw _fsFailure(e);
      } catch (e) {
        if (cancel?.isCancelled ?? false) {
          throw const UpdateFailure(
            UpdateErrorKind.cancelled,
            'Download cancelled.',
          );
        }
        throw const UpdateFailure(
          UpdateErrorKind.interrupted,
          'The download was interrupted. Try again to pick up where it '
          'left off.',
        );
      } finally {
        await sink.close();
      }
      if (total >= 0 && received != total) {
        throw const UpdateFailure(
          UpdateErrorKind.interrupted,
          'The download was interrupted. Try again to pick up where it left '
          'off.',
        );
      }
      return;
    }
    throw const UpdateFailure(
      UpdateErrorKind.unknown,
      "GitHub didn't send the update. Try again, or download it from the "
      'release page.',
    );
  }

  static UpdateFailure _failure(DioException e) {
    if (e.type == DioExceptionType.cancel) {
      return const UpdateFailure(
        UpdateErrorKind.cancelled,
        'Download cancelled.',
      );
    }
    if (e.error is FileSystemException) {
      return _fsFailure(e.error! as FileSystemException);
    }
    if (e.error is SocketException || e.error is HandshakeException) {
      return const UpdateFailure(
        UpdateErrorKind.offline,
        "Can't reach GitHub. Check your internet connection and try again.",
      );
    }
    return switch (e.type) {
      DioExceptionType.connectionError ||
      DioExceptionType.connectionTimeout => const UpdateFailure(
        UpdateErrorKind.offline,
        "Can't reach GitHub. Check your internet connection and try again.",
      ),
      _ => const UpdateFailure(
        UpdateErrorKind.interrupted,
        'The download was interrupted. Try again to pick up where it left '
        'off.',
      ),
    };
  }

  static UpdateFailure _fsFailure(FileSystemException e) {
    final noSpace = e.osError?.errorCode == 28; // ENOSPC
    return UpdateFailure(
      noSpace ? UpdateErrorKind.storage : UpdateErrorKind.unknown,
      noSpace
          ? 'Not enough storage for the update. Free up some space and try '
                'again.'
          : "Couldn't save the update on this phone.",
    );
  }
}

/// The SHA-256 of [file], lowercase hex (streamed, not read into memory).
Future<String> computeSha256(File file) async =>
    (await sha256.bind(file.openRead()).first).toString();

/// Whether [file] is exactly the release that was announced.
Future<bool> verifySha256(File file, String expected) async {
  final want = normaliseSha256(expected);
  if (want == null) return false;
  return await computeSha256(file) == want;
}
