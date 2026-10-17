import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:serafim/src/data/models/app_update.dart';

/// What the system installer did.
enum InstallOutcome { installed, cancelled, failed }

/// A downloaded APK, as Android reads it.
class ApkInfo {
  const ApkInfo({
    required this.packageName,
    required this.versionCode,
    required this.sameSigner,
    required this.samePackage,
  });

  final String packageName;

  /// It is Serafim (not some other app).
  final bool samePackage;
  final int versionCode;

  /// Signed with the same key as the installed app (otherwise Android would
  /// refuse to install it over this one).
  final bool sameSigner;
}

/// Android's package installer, through MainActivity's `serafim/updater`
/// channel. Behind an interface so the update flow can be tested.
abstract class AppInstaller {
  /// False off Android: in-app updates are Android-only.
  bool get supported;

  Future<AppVersion?> installedVersion();
  Future<int> freeBytes();
  Future<bool> canInstallPackages();
  Future<void> openInstallSettings();
  Future<ApkInfo?> inspectApk(String path);
  Future<InstallOutcome> install(String path);
}

class ChannelAppInstaller implements AppInstaller {
  static const _channel = MethodChannel('serafim/updater');

  @override
  bool get supported => !kIsWeb && Platform.isAndroid;

  @override
  Future<AppVersion?> installedVersion() async {
    if (!supported) return null;
    final m = await _channel.invokeMapMethod<String, Object?>('versionInfo');
    if (m == null) return null;
    return AppVersion(
      name: m['versionName'] as String? ?? '?',
      code: (m['versionCode'] as num).toInt(),
    );
  }

  @override
  Future<int> freeBytes() async =>
      (await _channel.invokeMethod<num>('freeBytes'))?.toInt() ?? 0;

  @override
  Future<bool> canInstallPackages() async =>
      await _channel.invokeMethod<bool>('canInstallPackages') ?? false;

  @override
  Future<void> openInstallSettings() =>
      _channel.invokeMethod<void>('openInstallSettings');

  @override
  Future<ApkInfo?> inspectApk(String path) async {
    final m = await _channel.invokeMapMethod<String, Object?>('inspectApk', {
      'path': path,
    });
    if (m == null) return null;
    return ApkInfo(
      packageName: m['packageName'] as String? ?? '',
      versionCode: (m['versionCode'] as num?)?.toInt() ?? 0,
      sameSigner: m['sameSigner'] as bool? ?? false,
      samePackage: m['samePackage'] as bool? ?? false,
    );
  }

  @override
  Future<InstallOutcome> install(String path) async {
    final r = await _channel.invokeMethod<String>('install', {'path': path});
    return switch (r) {
      'installed' => InstallOutcome.installed,
      'cancelled' => InstallOutcome.cancelled,
      _ => InstallOutcome.failed,
    };
  }
}
