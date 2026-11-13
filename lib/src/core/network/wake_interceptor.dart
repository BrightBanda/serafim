import 'dart:async';

import 'package:dio/dio.dart';

/// Wakes a sleeping free-tier backend that the main route cannot wake.
///
/// The app reaches the backend through a Cloudflare Worker (some networks
/// cannot reach Render directly). Render answers `429` with
/// `x-render-routing: hibernate-rate-limited` to a sleeping server's requests
/// that come from Cloudflare's shared addresses, and never wakes it: waiting
/// and refreshing do nothing. A request straight to Render does wake it.
///
/// So on exactly that answer this sends one request to [directUrl] (which
/// holds until the server is up), then replays the original request once.
/// Anything else, including a real rate limit, passes through untouched, and
/// if the direct address cannot be reached (a network that blocks Render) the
/// original error is kept.
class WakeInterceptor extends Interceptor {
  WakeInterceptor({
    required this.directUrl,
    Dio? wakeClient,
    this.wakeTimeout = const Duration(seconds: 90),
  }) : _wakeClient = wakeClient ?? Dio();

  /// Render's own address for the backend, e.g.
  /// `https://serafim-backend.onrender.com`. Empty turns this off.
  final String directUrl;

  /// Waking from sleep takes about a minute.
  final Duration wakeTimeout;

  /// Bare client: no interceptors, so waking can never recurse into this one.
  final Dio _wakeClient;

  /// Marks a request that was already replayed after waking the server, so a
  /// server that keeps refusing cannot put us in a loop.
  static const _replayedKey = 'serafim.wake.replayed';

  late final Dio _client;
  Future<bool>? _inFlightWake;

  void attachTo(Dio dio) {
    _client = dio;
    dio.interceptors.add(this);
  }

  /// True for the one answer that means "asleep, and not waking for you".
  static bool isSleepingRefusal(Response<dynamic>? response) {
    if (response?.statusCode != 429) return false;
    final routing = response?.headers.value('x-render-routing') ?? '';
    return routing.contains('hibernate');
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final options = err.requestOptions;
    if (directUrl.isEmpty ||
        !isSleepingRefusal(err.response) ||
        options.extra[_replayedKey] == true) {
      handler.next(err);
      return;
    }

    if (!await _wake()) {
      handler.next(err);
      return;
    }

    options.extra[_replayedKey] = true;
    try {
      handler.resolve(await _client.fetch<dynamic>(options));
    } on DioException catch (retryError) {
      handler.next(retryError);
    }
  }

  /// One wake-up at a time: ten requests that find the server asleep share a
  /// single direct request.
  Future<bool> _wake() {
    return _inFlightWake ??= _performWake().whenComplete(() {
      _inFlightWake = null;
    });
  }

  Future<bool> _performWake() async {
    try {
      final response = await _wakeClient.get<dynamic>(
        '${directUrl.replaceAll(RegExp(r'/+$'), '')}/health',
        options: Options(
          sendTimeout: wakeTimeout,
          receiveTimeout: wakeTimeout,
          validateStatus: (_) => true,
        ),
      );
      return (response.statusCode ?? 500) < 500;
    } on DioException {
      return false;
    }
  }
}
