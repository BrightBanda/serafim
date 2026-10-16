import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:flutter/services.dart'
    show MissingPluginException, PlatformException;
import 'package:isar_community/isar.dart' show IsarError;
import 'package:serafim/src/core/network/api_exception.dart';

const _generic = 'Something went wrong. Please try again.';

/// Turns *any* error into a sentence a person can act on. Screens show this,
/// never `error.toString()`.
///
/// The original error is still printed in debug builds so it can be diagnosed,
/// but it never reaches the user.
String humanError(Object? error, {String? fallback}) {
  if (kDebugMode && error != null) debugPrint('[error] $error');
  final fb = fallback ?? _generic;

  if (error == null) return fb;
  if (error is ApiException) return error.message;
  if (error is DioException) return ApiException.fromDio(error).message;

  if (error is SocketException ||
      error is HandshakeException ||
      error is HttpException) {
    return "Can't reach the server. Check your internet connection and try again.";
  }
  if (error is TimeoutException) {
    return 'That took too long. Please try again.';
  }
  if (error is FormatException) {
    return 'Something unexpected came back from the server. Please try again.';
  }
  if (error is FileSystemException) {
    return "Couldn't read or save that file. Check that your phone has free storage.";
  }
  if (error is PlatformException) return _platformMessage(error, fb);
  if (error is MissingPluginException ||
      error is UnimplementedError ||
      error is UnsupportedError) {
    return "That isn't available on this device.";
  }
  if (error is IsarError) {
    return "Couldn't read your messages on this phone. Restart the app and try again.";
  }
  if (error is StateError || error is TypeError || error is AssertionError) {
    return fb;
  }
  return fb;
}

String _platformMessage(PlatformException e, String fallback) {
  final code = e.code.toLowerCase();
  if (code.contains('photo_access_denied') ||
      code.contains('photo') && code.contains('denied')) {
    return 'Allow Serafim to use your photos in your phone settings, then try again.';
  }
  if (code.contains('camera_access_denied') ||
      code.contains('camera') && code.contains('denied')) {
    return 'Allow Serafim to use your camera in your phone settings, then try again.';
  }
  if (code.contains('already_active')) {
    return 'Please finish what you were doing first, then try again.';
  }
  if (code.contains('network')) {
    return "Can't reach the internet. Check your connection and try again.";
  }
  return fallback;
}
