import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter/widgets.dart' show AppLifecycleListener;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:serafim/src/core/platform/app_installer.dart';
import 'package:serafim/src/data/models/app_update.dart';
import 'package:serafim/src/data/services/update_service.dart';
import 'package:serafim/src/providers/app_providers.dart';
import 'package:serafim/src/providers/network_providers.dart';
import 'package:serafim/src/providers/settings_providers.dart';

final appInstallerProvider = Provider<AppInstaller>(
  (ref) => ChannelAppInstaller(),
);

/// The installed app's version, or null where in-app updates don't apply
/// (not Android).
final installedVersionProvider = FutureProvider<AppVersion?>((ref) async {
  final installer = ref.watch(appInstallerProvider);
  if (!installer.supported) return null;
  try {
    return await installer.installedVersion();
  } catch (_) {
    return null;
  }
});

/// A plain client for GitHub. Deliberately not the API client: it has no
/// auth interceptor, so the Serafim session token never goes to GitHub.
final githubDioProvider = Provider<Dio>(
  (ref) => Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 60),
      headers: {'user-agent': 'Serafim-Android-Updater'},
    ),
  ),
);

final updateServiceProvider = Provider<UpdateService>(
  (ref) => UpdateService(
    api: ref.watch(apiDioProvider),
    github: ref.watch(githubDioProvider),
    repo: ref.watch(appConfigProvider).updateRepo,
  ),
);

final apkDownloaderProvider = Provider<ApkDownloader>(
  (ref) => ApkDownloader(
    dio: ref.watch(githubDioProvider),
    repo: ref.watch(appConfigProvider).updateRepo,
  ),
);

/// Where downloaded updates go (shared with the installer via FileProvider,
/// see android/app/src/main/res/xml/update_paths.xml). Replaced in tests.
Future<Directory> Function() updatesDirectory = () async {
  final dir = Directory('${(await getTemporaryDirectory()).path}/updates');
  if (!await dir.exists()) await dir.create(recursive: true);
  return dir;
};

// ------------------------------------------------------------ launch check

/// What the launch check found.
class UpdateStatus {
  const UpdateStatus({this.installed, this.available, this.mustUpdate = false});

  final AppVersion? installed;

  /// The newest release newer than what is installed, if any.
  final AppUpdate? available;

  /// This version is below the newest mandatory release: the app is blocked
  /// until it updates.
  final bool mustUpdate;

  static const none = UpdateStatus();
}

/// Checks for a newer release at launch: the Serafim server (which knows
/// mandatory releases and verified checksums) and GitHub's latest release.
/// At most once every [interval]; otherwise, and whenever a check fails, the
/// last result is used. Failures are silent.
class UpdateCheckController extends AsyncNotifier<UpdateStatus> {
  static const interval = Duration(hours: 6);

  static const _checkedAt = 'update.checkedAt';
  static const _server = 'update.server';
  static const _github = 'update.github';
  static const _etag = 'update.etag';
  static const _dismissed = 'update.dismissed';

  /// Shortened in tests.
  static DateTime Function() now = DateTime.now;

  @override
  Future<UpdateStatus> build() async {
    final installed = await ref.watch(installedVersionProvider.future);
    if (installed == null) return UpdateStatus.none;
    unawaited(ref.read(updateFlowProvider.notifier).cleanUpDownloads());
    return _check(installed, force: false);
  }

  /// Checks again now (pull to refresh, Retry on the blocking screen).
  Future<void> refresh() async {
    final installed = await ref.read(installedVersionProvider.future);
    if (installed == null) return;
    state = AsyncData(await _check(installed, force: true));
  }

  Future<UpdateStatus> _check(
    AppVersion installed, {
    required bool force,
  }) async {
    final prefs = ref.read(sharedPreferencesProvider);
    final last = DateTime.tryParse(prefs.getString(_checkedAt) ?? '');
    final due = force || last == null || now().difference(last) >= interval;

    var server = _readServer();
    var github = AppUpdate.tryParse(_decode(prefs.getString(_github)));

    if (due) {
      final service = ref.read(updateServiceProvider);
      try {
        server = await service.serverInfo();
        await prefs.setString(
          _server,
          jsonEncode({
            'latest': server.latest?.toJson(),
            'min_version_code': server.minVersionCode,
          }),
        );
      } catch (_) {
        // Keep the cached answer: a phone that can't reach the server must
        // still be blocked by a mandatory release it already knows about.
      }
      try {
        final r = await service.latestRelease(etag: prefs.getString(_etag));
        if (!r.unchanged) {
          github = r.release?.update;
          await prefs.setString(_github, jsonEncode(github?.toJson()));
          final etag = r.release?.etag;
          etag == null
              ? await prefs.remove(_etag)
              : await prefs.setString(_etag, etag);
        }
      } catch (_) {
        // Rate limited or offline: try again next time.
      }
      await prefs.setString(_checkedAt, now().toIso8601String());
    }
    return combine(installed, server, github);
  }

  ServerUpdateInfo? _readServer() {
    final json = _decode(
      ref.read(sharedPreferencesProvider).getString(_server),
    );
    if (json is! Map<String, dynamic>) return null;
    return ServerUpdateInfo(
      latest: AppUpdate.tryParse(json['latest']),
      minVersionCode: (json['min_version_code'] as num?)?.toInt() ?? 0,
    );
  }

  static Object? _decode(String? raw) {
    if (raw == null) return null;
    try {
      return jsonDecode(raw);
    } catch (_) {
      return null;
    }
  }

  /// The best update to offer. The server's copy wins for the same version
  /// (it carries the mandatory flag and an admin-checked checksum).
  static UpdateStatus combine(
    AppVersion installed,
    ServerUpdateInfo? server,
    AppUpdate? github,
  ) {
    final candidates = [
      if (server?.latest != null && server!.latest!.isNewerThan(installed))
        server.latest!,
      if (github != null && github.isNewerThan(installed)) github,
    ]..sort((a, b) => b.versionCode.compareTo(a.versionCode));
    var best = candidates.isEmpty ? null : candidates.first;
    final serverLatest = server?.latest;
    if (best != null &&
        serverLatest != null &&
        serverLatest.versionCode == best.versionCode) {
      best = serverLatest;
    }
    final must = installed.code < (server?.minVersionCode ?? 0);
    return UpdateStatus(
      installed: installed,
      available: must && best != null ? best.copyWith(mandatory: true) : best,
      mustUpdate: must,
    );
  }

  /// "Not now" on the launch prompt: don't offer this version again.
  Future<void> dismiss(int versionCode) =>
      ref.read(sharedPreferencesProvider).setInt(_dismissed, versionCode);

  bool isDismissed(int versionCode) =>
      (ref.read(sharedPreferencesProvider).getInt(_dismissed) ?? 0) >=
      versionCode;
}

final updateCheckProvider =
    AsyncNotifierProvider<UpdateCheckController, UpdateStatus>(
      UpdateCheckController.new,
    );

// ---------------------------------------------------- download and install

enum UpdatePhase {
  idle,
  preparing,
  downloading,
  verifying,
  needsPermission,
  installing,
  failed,
}

class UpdateFlowState {
  const UpdateFlowState({
    this.phase = UpdatePhase.idle,
    this.update,
    this.received = 0,
    this.total = -1,
    this.error,
  });

  final UpdatePhase phase;

  /// The release being installed.
  final AppUpdate? update;
  final int received;

  /// -1 while unknown.
  final int total;
  final UpdateFailure? error;

  bool get busy =>
      phase != UpdatePhase.idle &&
      phase != UpdatePhase.failed &&
      phase != UpdatePhase.needsPermission;

  double? get progress => total > 0 ? (received / total).clamp(0.0, 1.0) : null;
}

/// Downloads an update, checks it, and hands it to Android's installer:
///
/// 1. enough free space, then download (resumable, GitHub hosts only);
/// 2. SHA-256 must match the announcement, or the file is deleted;
/// 3. the APK must be Serafim, newer, and signed with the same key;
/// 4. "Install unknown apps" must be allowed — if not, the user is sent to
///    that setting and the install continues when they come back;
/// 5. the system installer asks the user to confirm.
class UpdateFlowController extends Notifier<UpdateFlowState> {
  AppInstaller get _installer => ref.read(appInstallerProvider);
  CancelToken? _cancel;
  File? _file;
  AppLifecycleListener? _lifecycle;

  @override
  UpdateFlowState build() {
    ref.onDispose(() => _lifecycle?.dispose());
    return const UpdateFlowState();
  }

  void _fail(UpdateFailure f) {
    state = UpdateFlowState(
      phase: UpdatePhase.failed,
      update: state.update,
      received: state.received,
      total: state.total,
      error: f,
    );
  }

  Future<void> start(AppUpdate update) async {
    if (state.busy) return;
    state = UpdateFlowState(phase: UpdatePhase.preparing, update: update);
    try {
      if (!_installer.supported) {
        throw const UpdateFailure(
          UpdateErrorKind.unknown,
          'Updates are installed from Serafim on Android.',
        );
      }
      if (!update.canVerify) {
        throw const UpdateFailure(
          UpdateErrorKind.unverifiable,
          "This release has no checksum, so it can't be checked and won't "
          'be installed from inside the app. Download it from the release '
          'page instead.',
        );
      }
      final installed = await _installer.installedVersion();
      if (installed != null && !update.isNewerThan(installed)) {
        throw const UpdateFailure(
          UpdateErrorKind.notNewer,
          'You already have this version or a newer one.',
        );
      }

      final dir = await updatesDirectory();
      final file = File('${dir.path}/serafim-${update.versionCode}.apk');
      _file = file;
      final have = await file.exists() ? await file.length() : 0;
      final needed = update.sizeBytes - have + 20 * 1024 * 1024;
      if (await _installer.freeBytes() < needed) {
        throw UpdateFailure(
          UpdateErrorKind.storage,
          'Not enough storage for the update (it needs about '
          '${formatBytes(update.sizeBytes)}). Free up some space and try '
          'again.',
        );
      }

      // An earlier download may already be complete and verified.
      final complete =
          have > 0 &&
          have == update.sizeBytes &&
          await verifySha256(file, update.sha256!);
      if (!complete) {
        _cancel = CancelToken();
        state = UpdateFlowState(
          phase: UpdatePhase.downloading,
          update: update,
          received: have,
          total: update.sizeBytes,
        );
        await ref
            .read(apkDownloaderProvider)
            .download(
              Uri.parse(update.apkUrl),
              file,
              cancel: _cancel,
              onProgress: (received, total) {
                if (state.phase != UpdatePhase.downloading) return;
                state = UpdateFlowState(
                  phase: UpdatePhase.downloading,
                  update: update,
                  received: received,
                  total: total > 0 ? total : update.sizeBytes,
                );
              },
            );
        state = UpdateFlowState(phase: UpdatePhase.verifying, update: update);
        if (!await verifySha256(file, update.sha256!)) {
          await _delete();
          throw const UpdateFailure(
            UpdateErrorKind.hashMismatch,
            "The download doesn't match the published update (it may be "
            "corrupted or tampered with), so it was deleted. Try again, or "
            'download it from the release page.',
          );
        }
      }

      final info = await _installer.inspectApk(file.path);
      if (info == null || !info.samePackage) {
        await _delete();
        throw const UpdateFailure(
          UpdateErrorKind.wrongApp,
          "The download isn't a Serafim update, so it won't be installed.",
        );
      }
      if (installed != null && info.versionCode <= installed.code) {
        await _delete();
        throw const UpdateFailure(
          UpdateErrorKind.notNewer,
          "The downloaded app isn't newer than the one you have.",
        );
      }
      if (!info.sameSigner) {
        await _delete();
        throw const UpdateFailure(
          UpdateErrorKind.wrongSigner,
          'This update is signed with a different key than the Serafim you '
          "have, so Android can't install it over this version. Uninstall "
          'Serafim and install the new version from the release page.',
        );
      }
      await _install(update);
    } on UpdateFailure catch (f) {
      if (f.kind == UpdateErrorKind.cancelled) {
        // Asked for: not an error to show.
        await _delete();
        state = const UpdateFlowState();
        return;
      }
      _fail(f);
    } on PlatformException catch (e) {
      await _delete();
      _fail(
        UpdateFailure(
          UpdateErrorKind.installFailed,
          e.message ?? "Android couldn't install the update.",
        ),
      );
    } catch (_) {
      _fail(
        const UpdateFailure(
          UpdateErrorKind.unknown,
          "Something went wrong while updating. Try again, or download it "
          'from the release page.',
        ),
      );
    } finally {
      _cancel = null;
    }
  }

  Future<void> _install(AppUpdate update) async {
    final file = _file;
    if (file == null) return;
    if (!await _installer.canInstallPackages()) {
      state = UpdateFlowState(
        phase: UpdatePhase.needsPermission,
        update: update,
      );
      // Carry on by itself when they come back from the setting.
      _lifecycle ??= AppLifecycleListener(onResume: continueAfterPermission);
      return;
    }
    state = UpdateFlowState(phase: UpdatePhase.installing, update: update);
    final outcome = await _installer.install(file.path);
    switch (outcome) {
      case InstallOutcome.installed:
        // Usually Android has already replaced the app by now.
        await _delete();
        state = const UpdateFlowState();
      case InstallOutcome.cancelled:
        // The verified file is kept so trying again is instant; it is
        // cleaned up at the next launch either way.
        throw const UpdateFailure(
          UpdateErrorKind.installerCancelled,
          'The update was not installed. Tap Try again when you are ready.',
        );
      case InstallOutcome.failed:
        await _delete();
        throw const UpdateFailure(
          UpdateErrorKind.installFailed,
          "Android couldn't install the update. Try again, or download it "
          'from the release page.',
        );
    }
  }

  /// Opens Serafim's "Install unknown apps" setting.
  Future<void> openInstallSettings() => _installer.openInstallSettings();

  /// After visiting the setting (called automatically on resume).
  Future<void> continueAfterPermission() async {
    if (state.phase != UpdatePhase.needsPermission) return;
    final update = state.update;
    if (update == null) return;
    if (!await _installer.canInstallPackages()) return; // Still not allowed.
    try {
      await _install(update);
    } on UpdateFailure catch (f) {
      _fail(f);
    } on PlatformException catch (e) {
      _fail(
        UpdateFailure(
          UpdateErrorKind.installFailed,
          e.message ?? "Android couldn't install the update.",
        ),
      );
    }
  }

  /// Stops a download (and throws the partial file away).
  void cancel() {
    if (state.phase == UpdatePhase.needsPermission) {
      _fail(
        const UpdateFailure(
          UpdateErrorKind.permissionDenied,
          'Serafim needs permission to install updates. Allow "Install '
          'unknown apps" for Serafim in settings, or download the update '
          'from the release page.',
        ),
      );
      return;
    }
    _cancel?.cancel();
  }

  void reset() {
    if (!state.busy) state = const UpdateFlowState();
  }

  Future<void> _delete() async {
    final f = _file;
    try {
      if (f != null && await f.exists()) await f.delete();
    } catch (_) {}
  }

  /// At launch: downloads left over from earlier (an update that installed,
  /// or one abandoned) are removed.
  Future<void> cleanUpDownloads() async {
    if (state.busy) return;
    try {
      final dir = await updatesDirectory();
      await for (final f in dir.list()) {
        if (f is File && f.path.endsWith('.apk')) await f.delete();
      }
    } catch (_) {}
  }
}

final updateFlowProvider =
    NotifierProvider<UpdateFlowController, UpdateFlowState>(
      UpdateFlowController.new,
    );
