import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serafim/src/core/platform/app_installer.dart';
import 'package:serafim/src/data/models/announcement.dart';
import 'package:serafim/src/data/models/app_update.dart';
import 'package:serafim/src/data/services/update_service.dart';
import 'package:serafim/src/providers/settings_providers.dart';
import 'package:serafim/src/providers/update_providers.dart';
import 'package:serafim/src/utils/update/update_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

const repo = 'BrightBanda/serafim';
const apkUrl =
    'https://github.com/$repo/releases/download/v1.1.0%2B2/serafim-1.1.0.apk';
final apkBytes = Uint8List.fromList(List.generate(4096, (i) => i % 251));
final apkSha = sha256.convert(apkBytes).toString();

AppUpdate release({
  int code = 2,
  String? sha,
  bool mandatory = false,
  int? size,
}) => AppUpdate(
  versionName: '1.1.0',
  versionCode: code,
  apkUrl: apkUrl,
  sha256: sha ?? apkSha,
  sizeBytes: size ?? apkBytes.length,
  mandatory: mandatory,
  changelog: 'Groups!',
);

const installed1 = AppVersion(name: '1.0.0', code: 1);

/// Answers requests from a table: url -> (status, headers, body).
class FakeNet implements HttpClientAdapter {
  final routes = <String, ResponseBody Function(RequestOptions)>{};
  final seen = <String>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions o,
    Stream<Uint8List>? _,
    Future<void>? __,
  ) async {
    seen.add(o.uri.toString());
    final r = routes[o.uri.toString()];
    if (r == null) return ResponseBody.fromString('', 404);
    return r(o);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody bytes(
  List<int> b, {
  int status = 200,
  Map<String, List<String>>? headers,
}) => ResponseBody(
  Stream.value(Uint8List.fromList(b)),
  status,
  headers: {
    'content-length': ['${b.length}'],
    ...?headers,
  },
);

ResponseBody redirect(String to) => ResponseBody.fromString(
  '',
  302,
  headers: {
    'location': [to],
  },
);

class FakeInstaller implements AppInstaller {
  bool allowed = true;
  int free = 1 << 30;
  ApkInfo? info = const ApkInfo(
    packageName: 'com.binaryforge.serafim',
    versionCode: 2,
    sameSigner: true,
    samePackage: true,
  );
  InstallOutcome outcome = InstallOutcome.installed;
  final installs = <String>[];
  bool settingsOpened = false;

  @override
  bool get supported => true;
  @override
  Future<AppVersion?> installedVersion() async => installed1;
  List<String> abis = const ['arm64-v8a', 'armeabi-v7a'];

  @override
  Future<List<String>> supportedAbis() async => abis;

  @override
  Future<int> freeBytes() async => free;
  @override
  Future<bool> canInstallPackages() async => allowed;
  @override
  Future<void> openInstallSettings() async => settingsOpened = true;
  @override
  Future<ApkInfo?> inspectApk(String path) async => info;
  @override
  Future<InstallOutcome> install(String path) async {
    installs.add(path);
    return outcome;
  }
}

void main() {
  group('versions', () {
    test('release tags carry the version and code', () {
      expect(parseReleaseTag('v1.2.0+5'), (name: '1.2.0', code: 5));
      expect(parseReleaseTag('1.2.0+5'), (name: '1.2.0', code: 5));
      expect(parseReleaseTag('v1.2.0'), isNull);
      expect(parseReleaseTag('latest'), isNull);
    });

    test('only a higher version code counts as newer', () {
      expect(release(code: 2).isNewerThan(installed1), isTrue);
      expect(release(code: 1).isNewerThan(installed1), isFalse);
      expect(release(code: 0).isNewerThan(installed1), isFalse);
    });

    test('checksums are normalised; junk is rejected', () {
      expect(normaliseSha256('sha256:${'AB' * 32}'), 'ab' * 32);
      expect(normaliseSha256('nope'), isNull);
      expect(release(sha: 'nope').canVerify, isFalse);
    });
  });

  group('download allow-list', () {
    bool ok(String u, {bool redirect = false}) =>
        isAllowedDownloadUrl(Uri.parse(u), repo, redirect: redirect);

    test('only this repo\'s release APKs, over https', () {
      expect(ok(apkUrl), isTrue);
      expect(ok('http://github.com/$repo/releases/download/v1/a.apk'), isFalse);
      expect(
        ok('https://github.com/other/repo/releases/download/v1/a.apk'),
        isFalse,
      );
      expect(ok('https://github.com/$repo/archive/main.zip'), isFalse);
      expect(
        ok('https://github.com/$repo/releases/download/v1/a.exe'),
        isFalse,
      );
      expect(
        ok('https://github.com.evil.com/$repo/releases/download/v1/a.apk'),
        isFalse,
      );
      expect(
        ok('https://user@github.com/$repo/releases/download/v1/a.apk'),
        isFalse,
      );
      expect(
        ok('https://github.com:8443/$repo/releases/download/v1/a.apk'),
        isFalse,
      );
      expect(
        ok('https://objects.githubusercontent.com/x'),
        isFalse,
        reason: 'asset hosts only as a redirect target',
      );
    });

    test('redirects may only go to GitHub\'s asset hosts', () {
      expect(
        ok('https://objects.githubusercontent.com/abc', redirect: true),
        isTrue,
      );
      expect(
        ok('https://release-assets.githubusercontent.com/abc', redirect: true),
        isTrue,
      );
      expect(ok('https://evil.example/a.apk', redirect: true), isFalse);
      expect(
        ok('http://objects.githubusercontent.com/abc', redirect: true),
        isFalse,
      );
    });
  });

  group('hash verification', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('sha'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('matches the published SHA-256 exactly', () async {
      final f = File('${dir.path}/a.apk')..writeAsBytesSync(apkBytes);
      expect(await verifySha256(f, apkSha), isTrue);
      expect(await verifySha256(f, 'sha256:${apkSha.toUpperCase()}'), isTrue);
      expect(await verifySha256(f, 'f' * 64), isFalse);
      f.writeAsBytesSync([...apkBytes, 0]);
      expect(await verifySha256(f, apkSha), isFalse);
    });
  });

  group('downloader', () {
    late Directory dir;
    late FakeNet net;
    late ApkDownloader dl;
    const asset = 'https://objects.githubusercontent.com/asset?sig=1';

    setUp(() {
      dir = Directory.systemTemp.createTempSync('dl');
      net = FakeNet();
      dl = ApkDownloader(dio: Dio()..httpClientAdapter = net, repo: repo);
    });
    tearDown(() => dir.deleteSync(recursive: true));

    test('follows GitHub\'s redirect and saves the file', () async {
      net.routes[apkUrl] = (_) => redirect(asset);
      net.routes[asset] = (_) => bytes(apkBytes);
      final f = File('${dir.path}/a.apk');
      var last = 0;
      await dl.download(Uri.parse(apkUrl), f, onProgress: (r, t) => last = r);
      expect(f.readAsBytesSync(), apkBytes);
      expect(last, apkBytes.length);
    });

    test('a redirect anywhere else is refused before connecting', () async {
      net.routes[apkUrl] = (_) => redirect('https://evil.example/malware.apk');
      await expectLater(
        dl.download(
          Uri.parse(apkUrl),
          File('${dir.path}/a.apk'),
          onProgress: (_, _) {},
        ),
        throwsA(
          isA<UpdateFailure>().having(
            (f) => f.kind,
            'kind',
            UpdateErrorKind.badUrl,
          ),
        ),
      );
      expect(net.seen, [apkUrl]);
    });

    test('an interrupted download resumes with a Range request', () async {
      final f = File('${dir.path}/a.apk')
        ..writeAsBytesSync(apkBytes.sublist(0, 1000));
      String? range;
      net.routes[apkUrl] = (o) {
        range = o.headers['range'] as String?;
        return bytes(apkBytes.sublist(1000), status: 206);
      };
      await dl.download(Uri.parse(apkUrl), f, onProgress: (_, _) {});
      expect(range, 'bytes=1000-');
      expect(f.readAsBytesSync(), apkBytes);
    });

    test('a short download is reported as interrupted', () async {
      net.routes[apkUrl] = (_) => ResponseBody(
        Stream.value(Uint8List.fromList(apkBytes.sublist(0, 10))),
        200,
        headers: {
          'content-length': ['${apkBytes.length}'],
        },
      );
      await expectLater(
        dl.download(
          Uri.parse(apkUrl),
          File('${dir.path}/a.apk'),
          onProgress: (_, _) {},
        ),
        throwsA(
          isA<UpdateFailure>().having(
            (f) => f.kind,
            'kind',
            UpdateErrorKind.interrupted,
          ),
        ),
      );
    });
  });

  group('install flow', () {
    late Directory dir;
    late FakeNet net;
    late FakeInstaller installer;
    late ProviderContainer c;

    setUp(() async {
      dir = Directory.systemTemp.createTempSync('flow');
      updatesDirectory = () async => dir;
      net = FakeNet()..routes[apkUrl] = (_) => bytes(apkBytes);
      installer = FakeInstaller();
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      c = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          appInstallerProvider.overrideWithValue(installer),
          apkDownloaderProvider.overrideWithValue(
            ApkDownloader(dio: Dio()..httpClientAdapter = net, repo: repo),
          ),
        ],
      );
    });
    tearDown(() {
      c.dispose();
      dir.deleteSync(recursive: true);
    });

    UpdateFlowController flow() => c.read(updateFlowProvider.notifier);
    UpdateFlowState state() => c.read(updateFlowProvider);
    List<FileSystemEntity> files() => dir.listSync();

    test('downloads, verifies and hands the APK to the installer', () async {
      await flow().start(release());
      expect(installer.installs.single, endsWith('serafim-2.apk'));
      expect(state().phase, UpdatePhase.idle);
      expect(files(), isEmpty, reason: 'deleted after a successful install');
    });

    test('a hash mismatch deletes the file and installs nothing', () async {
      await flow().start(release(sha: 'f' * 64));
      expect(state().error!.kind, UpdateErrorKind.hashMismatch);
      expect(installer.installs, isEmpty);
      expect(files(), isEmpty);
    });

    test('an APK signed with another key is refused', () async {
      installer.info = const ApkInfo(
        packageName: 'com.binaryforge.serafim',
        versionCode: 2,
        sameSigner: false,
        samePackage: true,
      );
      await flow().start(release());
      expect(state().error!.kind, UpdateErrorKind.wrongSigner);
      expect(installer.installs, isEmpty);
      expect(files(), isEmpty);
    });

    test('a different app is refused', () async {
      installer.info = const ApkInfo(
        packageName: 'com.evil',
        versionCode: 9,
        sameSigner: false,
        samePackage: false,
      );
      await flow().start(release());
      expect(state().error!.kind, UpdateErrorKind.wrongApp);
    });

    test('a release without a checksum is never installed in-app', () async {
      await flow().start(release(sha: 'nope'));
      expect(state().error!.kind, UpdateErrorKind.unverifiable);
      expect(net.seen, isEmpty);
    });

    test('not enough storage is said up front', () async {
      installer.free = 10;
      await flow().start(release());
      expect(state().error!.kind, UpdateErrorKind.storage);
      expect(net.seen, isEmpty);
    });

    test('without "Install unknown apps" it asks, then continues', () async {
      installer.allowed = false;
      await flow().start(release());
      expect(state().phase, UpdatePhase.needsPermission);
      await flow().openInstallSettings();
      expect(installer.settingsOpened, isTrue);

      await flow().continueAfterPermission(); // still not allowed
      expect(state().phase, UpdatePhase.needsPermission);

      installer.allowed = true;
      await flow().continueAfterPermission();
      expect(installer.installs, hasLength(1));
    });

    test(
      'cancelling at the installer is reported and can be retried',
      () async {
        installer.outcome = InstallOutcome.cancelled;
        await flow().start(release());
        expect(state().error!.kind, UpdateErrorKind.installerCancelled);
        expect(state().error!.retryable, isTrue);
        installer.outcome = InstallOutcome.installed;
        net.seen.clear();
        await flow().start(release());
        expect(net.seen, isEmpty, reason: 'the verified file was reused');
        expect(installer.installs, hasLength(2));
      },
    );

    test('offline is a clear, retryable error', () async {
      final prefs = await SharedPreferences.getInstance();
      final offline = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          appInstallerProvider.overrideWithValue(installer),
          apkDownloaderProvider.overrideWithValue(
            ApkDownloader(
              dio: Dio()
                ..httpClientAdapter = _Throwing(
                  const SocketException('Network is unreachable'),
                ),
              repo: repo,
            ),
          ),
        ],
      );
      addTearDown(offline.dispose);
      await offline.read(updateFlowProvider.notifier).start(release());
      final error = offline.read(updateFlowProvider).error!;
      expect(error.kind, UpdateErrorKind.offline);
      expect(error.retryable, isTrue);
    });
  });

  group('launch check', () {
    test('a mandatory release blocks older versions; the server copy wins', () {
      final server = ServerUpdateInfo(
        latest: release(code: 3, mandatory: true),
        minVersionCode: 3,
      );
      final s = UpdateCheckController.combine(
        installed1,
        server,
        release(code: 3, sha: 'a' * 64),
      );
      expect(s.mustUpdate, isTrue);
      expect(s.available!.sha256, apkSha);
    });

    test('a newer GitHub release is offered even before it is announced', () {
      final s = UpdateCheckController.combine(
        installed1,
        ServerUpdateInfo(latest: release(code: 2)),
        release(code: 4),
      );
      expect(s.available!.versionCode, 4);
      expect(s.mustUpdate, isFalse);
    });

    test('up to date: nothing to offer', () {
      final s = UpdateCheckController.combine(
        const AppVersion(name: '9', code: 9),
        ServerUpdateInfo(latest: release(code: 3), minVersionCode: 3),
        null,
      );
      expect(s.available, isNull);
      expect(s.mustUpdate, isFalse);
    });

    test(
      'checks at most every 6 hours, and keeps blocking from cache offline',
      () async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        var calls = 0;
        var online = true;
        final service = _FakeService(() {
          calls++;
          if (!online) throw Exception('offline');
          return ServerUpdateInfo(
            latest: release(code: 3, mandatory: true),
            minVersionCode: 3,
          );
        });
        var clock = DateTime(2026, 1, 1, 9);
        UpdateCheckController.now = () => clock;
        addTearDown(() => UpdateCheckController.now = DateTime.now);
        ProviderContainer make() => ProviderContainer(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            appInstallerProvider.overrideWithValue(FakeInstaller()),
            updateServiceProvider.overrideWithValue(service),
          ],
        );

        var c = make();
        expect((await c.read(updateCheckProvider.future)).mustUpdate, isTrue);
        c.dispose();
        c = make();
        await c.read(updateCheckProvider.future);
        c.dispose();
        expect(calls, 1, reason: 'second launch within 6 h uses the cache');

        clock = clock.add(const Duration(hours: 7));
        online = false;
        c = make();
        expect((await c.read(updateCheckProvider.future)).mustUpdate, isTrue);
        c.dispose();
        expect(calls, 2);
      },
    );
  });

  group('announcements', () {
    test('older formats and unknown kinds degrade to text', () {
      final plain = Announcement.fromJson({
        'id': '1',
        'content': 'Hi',
        'created_at': '2026-01-01T00:00:00Z',
      });
      expect(plain.update, isNull);
      final unknown = Announcement.fromJson({
        'id': '2',
        'content': 'Fallback',
        'created_at': '2026-01-01T00:00:00Z',
        'kind': 'poll',
      });
      expect(unknown.update, isNull);
      expect(unknown.preview, 'Fallback');
      final broken = Announcement.fromJson({
        'id': '3',
        'content': 'Fallback',
        'created_at': '2026-01-01T00:00:00Z',
        'kind': 'app_update',
        'update': {'version_name': 1},
      });
      expect(broken.update, isNull);
    });

    test('update announcements round-trip through the saved copy', () {
      final a = Announcement(
        id: '1',
        content: 'x',
        createdAt: DateTime.utc(2026),
        update: release(),
      );
      final back = Announcement.fromJson(
        jsonDecode(jsonEncode(a.toJson())) as Map<String, dynamic>,
      );
      expect(back.update!.versionCode, 2);
      expect(back.preview, contains('1.1.0'));
    });
  });

  group('update card', () {
    Future<void> pump(WidgetTester tester, AppVersion? installed) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            installedVersionProvider.overrideWith((ref) async => installed),
          ],
          child: MaterialApp(
            home: Scaffold(body: UpdateCard(update: release())),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('shows Update only when the installed version is older', (
      tester,
    ) async {
      await pump(tester, installed1);
      expect(find.textContaining('Update ·'), findsOneWidget);
      expect(find.text('Serafim 1.1.0'), findsOneWidget);
      expect(find.text('Groups!'), findsOneWidget);
    });

    testWidgets('says Installed when you have it', (tester) async {
      await pump(tester, const AppVersion(name: '1.1.0', code: 2));
      expect(find.text('Installed'), findsOneWidget);
      expect(find.textContaining('Update ·'), findsNothing);
    });

    testWidgets('off Android it explains instead of offering a button', (
      tester,
    ) async {
      await pump(tester, null);
      expect(
        find.text('Updates are installed from Serafim on Android.'),
        findsOneWidget,
      );
    });
  });

  group('one APK per CPU type', () {
    const base = 'https://github.com/$repo/releases/download/v1.2.0%2B3';
    AppUpdate split() => AppUpdate(
      versionName: '1.2.0',
      versionCode: 3,
      apkUrl: '$base/serafim-1.2.0-arm64-v8a.apk',
      sha256: 'a' * 64,
      sizeBytes: 25,
      variants: [
        ApkVariant(
          abi: 'arm64-v8a',
          apkUrl: '$base/serafim-1.2.0-arm64-v8a.apk',
          sha256: 'a' * 64,
          sizeBytes: 25,
        ),
        ApkVariant(
          abi: 'armeabi-v7a',
          apkUrl: '$base/serafim-1.2.0-armeabi-v7a.apk',
          sha256: 'b' * 64,
          sizeBytes: 22,
        ),
      ],
    );

    test('each phone gets the build for its processor', () {
      final pixel = split().forDevice(['arm64-v8a']);
      expect(pixel!.apkUrl, endsWith('arm64-v8a.apk'));
      final itel = split().forDevice(['armeabi-v7a', 'armeabi']);
      expect(itel!.apkUrl, endsWith('armeabi-v7a.apk'));
      expect(itel.sha256, 'b' * 64);
      expect(itel.sizeBytes, 22);
      // A 64-bit phone that also runs 32-bit still prefers 64-bit.
      expect(
        split().forDevice(['arm64-v8a', 'armeabi-v7a'])!.apkUrl,
        endsWith('arm64-v8a.apk'),
      );
      expect(split().forDevice(['x86_64']), isNull);
      // Single-APK releases are offered as they are.
      expect(release().forDevice(['armeabi-v7a']), isNotNull);
    });

    test('file names say the CPU type', () {
      expect(abiFromFileName('serafim-1.2.0-arm64-v8a.apk'), 'arm64-v8a');
      expect(abiFromFileName('serafim-1.2.0-ARMEABI-V7A.apk'), 'armeabi-v7a');
      expect(abiFromFileName('serafim-1.0.0.apk'), isNull);
    });

    test('variants survive the saved copy', () {
      final back = AppUpdate.tryParse(jsonDecode(jsonEncode(split().toJson())));
      expect(back!.variants.map((v) => v.abi), ['arm64-v8a', 'armeabi-v7a']);
    });

    test(
      'a GitHub release with two APKs: arm64 on top, both as variants',
      () async {
        final net = FakeNet();
        net.routes['https://api.github.com/repos/$repo/releases/latest'] =
            (_) => ResponseBody.fromString(
              jsonEncode({
                'tag_name': 'v1.2.0+3',
                'body': 'Notes',
                'assets': [
                  {
                    'name': 'serafim-1.2.0-armeabi-v7a.apk',
                    'browser_download_url':
                        '$base/serafim-1.2.0-armeabi-v7a.apk',
                    'size': 22,
                    'digest': 'sha256:${'b' * 64}',
                  },
                  {
                    'name': 'serafim-1.2.0-arm64-v8a.apk',
                    'browser_download_url': '$base/serafim-1.2.0-arm64-v8a.apk',
                    'size': 25,
                    'digest': 'sha256:${'a' * 64}',
                  },
                ],
              }),
              200,
              headers: {
                'content-type': ['application/json'],
              },
            );
        final service = UpdateService(
          api: Dio(),
          github: Dio()..httpClientAdapter = net,
          repo: repo,
        );
        final u = (await service.latestRelease()).release!.update;
        expect(u.versionCode, 3);
        expect(u.apkUrl, endsWith('arm64-v8a.apk'));
        expect(u.variants, hasLength(2));
      },
    );

    test(
      'the install flow downloads the 32-bit build on a 32-bit phone',
      () async {
        final dir = Directory.systemTemp.createTempSync('abi');
        addTearDown(() => dir.deleteSync(recursive: true));
        updatesDirectory = () async => dir;
        final arm32 = '$base/serafim-1.2.0-armeabi-v7a.apk';
        final net = FakeNet()..routes[arm32] = (_) => bytes(apkBytes);
        final installer = FakeInstaller()
          ..abis = const ['armeabi-v7a', 'armeabi']
          ..info = const ApkInfo(
            packageName: 'com.binaryforge.serafim',
            versionCode: 3,
            sameSigner: true,
            samePackage: true,
          );
        SharedPreferences.setMockInitialValues({});
        final c = ProviderContainer(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(
              await SharedPreferences.getInstance(),
            ),
            appInstallerProvider.overrideWithValue(installer),
            apkDownloaderProvider.overrideWithValue(
              ApkDownloader(dio: Dio()..httpClientAdapter = net, repo: repo),
            ),
          ],
        );
        addTearDown(c.dispose);
        final update = AppUpdate(
          versionName: '1.2.0',
          versionCode: 3,
          apkUrl: '$base/serafim-1.2.0-arm64-v8a.apk',
          sha256: 'a' * 64,
          sizeBytes: 25,
          variants: [
            ApkVariant(
              abi: 'arm64-v8a',
              apkUrl: '$base/serafim-1.2.0-arm64-v8a.apk',
              sha256: 'a' * 64,
              sizeBytes: 25,
            ),
            ApkVariant(
              abi: 'armeabi-v7a',
              apkUrl: arm32,
              sha256: apkSha,
              sizeBytes: apkBytes.length,
            ),
          ],
        );
        await c.read(updateFlowProvider.notifier).start(update);
        expect(net.seen, [arm32]);
        expect(installer.installs, hasLength(1));
      },
    );

    test(
      'no build for the phone is said clearly, nothing downloaded',
      () async {
        final installer = FakeInstaller()..abis = const ['x86_64'];
        SharedPreferences.setMockInitialValues({});
        final c = ProviderContainer(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(
              await SharedPreferences.getInstance(),
            ),
            appInstallerProvider.overrideWithValue(installer),
          ],
        );
        addTearDown(c.dispose);
        await c.read(updateFlowProvider.notifier).start(split());
        expect(
          c.read(updateFlowProvider).error!.kind,
          UpdateErrorKind.incompatible,
        );
      },
    );
  });
}

class _Throwing implements HttpClientAdapter {
  _Throwing(this.error);
  final Object error;
  @override
  Future<ResponseBody> fetch(
    RequestOptions o,
    Stream<Uint8List>? _,
    Future<void>? __,
  ) => Future.error(
    error is DioException
        ? (error as DioException).copyWith(requestOptions: o)
        : error,
  );
  @override
  void close({bool force = false}) {}
}

class _FakeService extends UpdateService {
  _FakeService(this.answer) : super(api: Dio(), github: Dio(), repo: repo);
  final ServerUpdateInfo Function() answer;

  @override
  Future<ServerUpdateInfo> serverInfo() async => answer();

  @override
  Future<({GitHubRelease? release, bool unchanged})> latestRelease({
    String? etag,
  }) async => (release: null, unchanged: false);
}
