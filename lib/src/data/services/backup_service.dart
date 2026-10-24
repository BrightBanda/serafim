import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:serafim/src/core/network/api_exception.dart';
import 'package:serafim/src/data/local/isar_service.dart';
import 'package:serafim/src/data/services/google_auth_service.dart';

/// A backup stored in Google Drive.
class DriveBackup {
  const DriveBackup({required this.id, required this.modified, this.size});

  final String id;
  final DateTime modified;
  final int? size;
}

/// Keeps the chat database safe across app updates and reinstalls.
///
/// Two places: a file the person saves wherever they like (it survives an
/// uninstall because it is outside the app's storage), and the app's private
/// folder in their Google Drive. Both hold the same thing — a copy of the
/// local database. Photos and voice notes live in files on the phone and are
/// not part of it.
class BackupService {
  BackupService({
    required IsarService isar,
    required GoogleAuthService google,
    Dio? dio,
  }) : _isar = isar,
       _google = google,
       _dio = dio ?? Dio();

  final IsarService _isar;
  final GoogleAuthService _google;
  final Dio _dio;

  static const _driveName = 'serafim-backup.isar';
  static const _files = 'https://www.googleapis.com/drive/v3/files';
  static const _upload = 'https://www.googleapis.com/upload/drive/v3/files';

  Future<File> _snapshot() async {
    final dir = await getTemporaryDirectory();
    final stamp = DateTime.now().toIso8601String().substring(0, 10);
    final path = '${dir.path}/serafim-$stamp.isar';
    try {
      await _isar.snapshotTo(path);
    } on FileSystemException catch (e) {
      final file = File(path);
      if (await file.exists()) await file.delete();
      // 28 is ENOSPC, "no space left on device".
      throw ApiException(
        e.osError?.errorCode == 28
            ? 'Not enough free space on this phone to make a backup.'
            : 'Could not prepare the backup on this phone.',
      );
    }
    return File(path);
  }

  // ---------------------------------------------------------------- file

  /// Asks where to save, and writes the backup there. Returns false if the
  /// person backed out.
  Future<bool> exportToFile() async {
    final snapshot = await _snapshot();
    try {
      final saved = await FilePicker.saveFile(
        dialogTitle: 'Save Serafim backup',
        fileName: snapshot.uri.pathSegments.last,
        bytes: await snapshot.readAsBytes(),
      );
      return saved != null;
    } finally {
      await snapshot.delete();
    }
  }

  /// Asks for a backup file and restores it. Returns false if the person
  /// backed out; throws [ApiException] if the file is not a usable backup.
  Future<bool> restoreFromFile() async {
    final picked = await FilePicker.pickFiles(
      dialogTitle: 'Choose a Serafim backup',
      type: FileType.any,
    );
    final path = picked?.files.single.path;
    if (path == null) return false;
    await _restore(path);
    return true;
  }

  Future<void> _restore(String path) async {
    if (!await _isar.isValidBackup(path)) {
      throw const ApiException(
        'That file is not a Serafim backup, or it is from a newer version.',
      );
    }
    await _isar.restoreFrom(path);
  }

  // --------------------------------------------------------------- Drive

  Options _auth(String token) =>
      Options(headers: {'Authorization': 'Bearer $token'});

  Future<T> _drive<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      throw ApiException(
        code == 403
            ? 'Google Drive refused access. Allow Serafim to use its backup '
                  'folder and try again.'
            : 'Google Drive request failed'
                  '${code == null ? '' : ' ($code)'}. Check your connection.',
      );
    }
  }

  /// The newest backup in Drive, or null if there is none.
  Future<DriveBackup?> latestDriveBackup() async {
    final token = await _google.driveAccessToken();
    return _latest(token);
  }

  Future<DriveBackup?> _latest(String token) => _drive(() async {
    final res = await _dio.get<Map<String, dynamic>>(
      _files,
      queryParameters: {
        'spaces': 'appDataFolder',
        'q': "name = '$_driveName' and trashed = false",
        'orderBy': 'modifiedTime desc',
        'pageSize': 1,
        'fields': 'files(id,modifiedTime,size)',
      },
      options: _auth(token),
    );
    final files = res.data?['files'] as List? ?? const [];
    if (files.isEmpty) return null;
    final f = files.first as Map<String, dynamic>;
    return DriveBackup(
      id: f['id'] as String,
      modified: DateTime.parse(f['modifiedTime'] as String).toLocal(),
      size: int.tryParse('${f['size']}'),
    );
  });

  /// Uploads the current database, replacing the previous backup. With
  /// [interactive] false nothing is shown to the person (automatic backups);
  /// see [GoogleAuthService.driveAccessToken].
  Future<DriveBackup> backUpToDrive({bool interactive = true}) async {
    final token = await _google.driveAccessToken(interactive: interactive);
    final snapshot = await _snapshot();
    try {
      final bytes = await snapshot.readAsBytes();
      final existing = await _latest(token);
      const boundary = 'serafim-backup-boundary';
      final meta = jsonEncode({
        'name': _driveName,
        if (existing == null) 'parents': ['appDataFolder'],
      });
      final body = <int>[
        ...utf8.encode(
          '--$boundary\r\nContent-Type: application/json; charset=UTF-8'
          '\r\n\r\n$meta\r\n--$boundary\r\n'
          'Content-Type: application/octet-stream\r\n\r\n',
        ),
        ...bytes,
        ...utf8.encode('\r\n--$boundary--'),
      ];
      final url = existing == null ? _upload : '$_upload/${existing.id}';
      await _drive(
        () => _dio.request<dynamic>(
          url,
          queryParameters: {'uploadType': 'multipart'},
          data: Stream.fromIterable([body]),
          options: Options(
            method: existing == null ? 'POST' : 'PATCH',
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'multipart/related; boundary=$boundary',
              'Content-Length': body.length,
            },
          ),
        ),
      );
      return (await _latest(token))!;
    } finally {
      await snapshot.delete();
    }
  }

  /// Downloads the Drive backup and restores it. Returns false if Drive has
  /// no backup.
  Future<bool> restoreFromDrive() async {
    final token = await _google.driveAccessToken();
    final latest = await _latest(token);
    if (latest == null) return false;
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/serafim-restore.isar';
    try {
      await _drive(
        () => _dio.download(
          '$_files/${latest.id}',
          path,
          queryParameters: {'alt': 'media'},
          options: _auth(token),
        ),
      );
      await _restore(path);
      return true;
    } finally {
      final f = File(path);
      if (await f.exists()) await f.delete();
    }
  }
}
