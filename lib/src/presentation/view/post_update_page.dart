import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serafim/src/core/errors/human_error.dart';
import 'package:serafim/src/data/models/app_update.dart';
import 'package:serafim/src/data/services/update_service.dart';
import 'package:serafim/src/providers/official_providers.dart';
import 'package:serafim/src/providers/update_providers.dart';
import 'package:serafim/src/utils/app_top_bar.dart';
import 'package:serafim/src/utils/serafim_button.dart';
import 'package:serafim/src/utils/settings_widgets.dart';
import 'package:serafim/src/utils/themes/app_colors.dart';
import 'package:serafim/src/utils/themes/app_text_styles.dart';
import 'package:serafim/src/utils/ui_text_field.dart';

/// Admin only: builds an update announcement from the latest GitHub release
/// (version, APK link, size, SHA-256, notes) so nothing is typed by hand.
/// The server re-checks everything and refuses non-admins.
class PostUpdatePage extends ConsumerStatefulWidget {
  const PostUpdatePage({super.key});

  @override
  ConsumerState<PostUpdatePage> createState() => _PostUpdatePageState();
}

class _PostUpdatePageState extends ConsumerState<PostUpdatePage> {
  final _name = TextEditingController();
  final _code = TextEditingController();
  final _url = TextEditingController();
  final _sha = TextEditingController();
  final _size = TextEditingController();
  final _notes = TextEditingController();
  bool _mandatory = false;

  /// Per-CPU builds found on the release (empty for a single-APK release).
  List<ApkVariant> _variants = const [];
  bool _fetching = false;
  bool _posting = false;
  double? _hashProgress;
  CancelToken? _hashCancel;
  String? _error;

  @override
  void dispose() {
    for (final c in [_name, _code, _url, _sha, _size, _notes]) {
      c.dispose();
    }
    _hashCancel?.cancel();
    super.dispose();
  }

  Future<void> _fetchLatest() async {
    setState(() {
      _fetching = true;
      _error = null;
    });
    try {
      final r = await ref.read(updateServiceProvider).latestRelease();
      final u = r.release?.update;
      if (u == null) {
        _error =
            'No usable release found. The latest release must be published '
            '(not a draft), tagged like v1.2.0+5, with an .apk attached.';
      } else {
        _name.text = u.versionName;
        _code.text = '${u.versionCode}';
        _url.text = u.apkUrl;
        _size.text = '${u.sizeBytes}';
        _sha.text = u.sha256 ?? '';
        _notes.text = u.changelog;
        _variants = u.variants;
        if (u.sha256 == null || u.variants.any((v) => v.sha256 == null)) {
          _error = "GitHub didn't publish every checksum. Tap Compute SHA-256.";
        }
      }
    } catch (e) {
      _error = humanError(e, fallback: "Couldn't reach GitHub.");
    } finally {
      if (mounted) setState(() => _fetching = false);
    }
  }

  /// Downloads each APK whose checksum is missing (same allow-listed
  /// downloader) and hashes it.
  Future<void> _computeHash() async {
    final dir = await updatesDirectory();
    final file = File('${dir.path}/hash-check.apk');
    _hashCancel = CancelToken();
    setState(() {
      _hashProgress = 0;
      _error = null;
    });
    Future<(String, int)> hash(String url) async {
      if (await file.exists()) await file.delete();
      await ref
          .read(apkDownloaderProvider)
          .download(
            Uri.parse(url),
            file,
            cancel: _hashCancel,
            onProgress: (r, t) {
              if (mounted && t > 0) setState(() => _hashProgress = r / t);
            },
          );
      return (await computeSha256(file), await file.length());
    }

    try {
      if (_variants.isEmpty) {
        final (sha, size) = await hash(_url.text.trim());
        _sha.text = sha;
        _size.text = '$size';
      } else {
        final done = <ApkVariant>[];
        for (final v in _variants) {
          if (v.sha256 != null) {
            done.add(v);
            continue;
          }
          final (sha, size) = await hash(v.apkUrl);
          done.add(
            ApkVariant(
              abi: v.abi,
              apkUrl: v.apkUrl,
              sha256: sha,
              sizeBytes: size,
            ),
          );
          if (v.apkUrl == _url.text.trim()) {
            _sha.text = sha;
            _size.text = '$size';
          }
        }
        _variants = done;
      }
    } on UpdateFailure catch (f) {
      _error = f.message;
    } catch (e) {
      _error = humanError(e);
    } finally {
      try {
        if (await file.exists()) await file.delete();
      } catch (_) {}
      if (mounted) setState(() => _hashProgress = null);
    }
  }

  AppUpdate? _build() {
    final repo = ref.read(updateServiceProvider).repo;
    final code = int.tryParse(_code.text.trim());
    final size = int.tryParse(_size.text.trim());
    final sha = normaliseSha256(_sha.text);
    final url = Uri.tryParse(_url.text.trim());
    String? problem;
    if (!RegExp(r'^\d+\.\d+\.\d+$').hasMatch(_name.text.trim())) {
      problem = 'The version must look like 1.2.3.';
    } else if (code == null || code <= 0) {
      problem = 'The version code must be a positive number.';
    } else if (url == null || !isAllowedDownloadUrl(url, repo)) {
      problem =
          'The APK link must be a release download from github.com/$repo.';
    } else if (sha == null) {
      problem = 'The SHA-256 must be 64 hex characters.';
    } else if (size == null || size <= 0) {
      problem = 'The size must be the APK size in bytes.';
    } else if (_variants.any((v) => v.sha256 == null)) {
      problem = 'Every build needs a SHA-256. Tap Compute SHA-256.';
    }
    if (problem != null) {
      setState(() => _error = problem);
      return null;
    }
    return AppUpdate(
      versionName: _name.text.trim(),
      versionCode: code!,
      apkUrl: url.toString(),
      sha256: sha,
      sizeBytes: size!,
      changelog: _notes.text.trim(),
      mandatory: _mandatory,
      variants: _variants,
    );
  }

  Future<void> _post() async {
    final update = _build();
    if (update == null) return;
    setState(() {
      _posting = true;
      _error = null;
    });
    final error = await ref
        .read(officialChatProvider.notifier)
        .postUpdate(update);
    if (!mounted) return;
    if (error == null) {
      Navigator.of(context).pop();
    } else {
      setState(() {
        _posting = false;
        _error = error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final installed = ref.watch(installedVersionProvider).value;
    final hashing = _hashProgress != null;
    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppTopBar(
        title: 'ANNOUNCE UPDATE',
        onBack: _posting ? null : () => Navigator.of(context).pop(),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          children: [
            Text(
              'Fill this in from the latest GitHub release, check it, and '
              'post. Everyone gets the update card in this chat.',
              style: AppTextStyles.smallDim,
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _fetching || hashing ? null : _fetchLatest,
              icon: _fetching
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.download_for_offline_outlined, size: 18),
              label: const Text('Fill from the latest GitHub release'),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: UiTextField(
                    label: 'Version',
                    controller: _name,
                    hintText: '1.2.0',
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: UiTextField(
                    label: 'Version code',
                    controller: _code,
                    hintText: '5',
                    keyboardType: TextInputType.number,
                  ),
                ),
              ],
            ),
            if (installed != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'This phone has ${installed.name} (code ${installed.code}). '
                  'The new code must be higher.',
                  style: AppTextStyles.smallDim,
                ),
              ),
            const SizedBox(height: 12),
            UiTextField(label: 'APK download link', controller: _url),
            const SizedBox(height: 12),
            UiTextField(label: 'SHA-256', controller: _sha),
            const SizedBox(height: 6),
            if (hashing)
              LinearProgressIndicator(
                value: _hashProgress,
                color: AppColors.primary,
              )
            else
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: _fetching ? null : _computeHash,
                  child: Text(
                    'Compute SHA-256 by downloading the APK',
                    style: AppTextStyles.linkText,
                  ),
                ),
              ),
            if (_variants.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text('BUILDS', style: AppTextStyles.fieldLabel),
              for (final v in _variants)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '${v.abi} · ${formatBytes(v.sizeBytes)} · '
                    '${v.sha256 == null ? 'checksum missing' : 'checksum ${v.sha256!.substring(0, 12)}…'}',
                    style: AppTextStyles.smallDim,
                  ),
                ),
              const SizedBox(height: 6),
            ],
            const SizedBox(height: 6),
            UiTextField(
              label: 'Size (bytes)',
              controller: _size,
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 12),
            UiTextField(
              label: "What's new",
              controller: _notes,
              maxLines: 8,
              minLines: 3,
              maxLength: 4000,
              autocorrect: true,
            ),
            const SizedBox(height: 12),
            SettingsSwitchRow(
              title: 'Required update',
              subtitle:
                  'Older versions are blocked until they install this one. Use '
                  'only for breaking changes.',
              value: _mandatory,
              onChanged: (v) => setState(() => _mandatory = v),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(
                _error!,
                style: AppTextStyles.body.copyWith(color: AppColors.rustPale),
              ),
            ],
            const SizedBox(height: 16),
            SerafimButton(
              label: _posting ? 'Posting…' : 'Post update',
              onPressed: _posting || hashing || _fetching ? null : _post,
            ),
          ],
        ),
      ),
    );
  }
}
