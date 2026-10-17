import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serafim/src/data/models/link_preview.dart';
import 'package:serafim/src/data/services/link_preview_service.dart';
import 'package:serafim/src/providers/network_providers.dart';
import 'package:serafim/src/providers/settings_providers.dart';

final linkPreviewServiceProvider = Provider<LinkPreviewService>(
  (ref) => LinkPreviewService(ref.watch(apiDioProvider)),
);

/// The preview for one URL: from the phone's cache when available, else the
/// server (and then cached). Null means "show a plain link" — no metadata,
/// unreachable, timed out or offline all end up there.
final linkPreviewProvider = FutureProvider.family<LinkPreview?, String>((
  ref,
  url,
) async {
  final cache = ref.read(localCacheProvider);
  final (found, saved) = cache.linkPreview(url);
  if (found) return saved;
  try {
    final fresh = await ref.read(linkPreviewServiceProvider).fetch(url);
    await cache.saveLinkPreview(url, fresh);
    return fresh;
  } catch (_) {
    // Network trouble: don't cache, so it is tried again next time.
    return null;
  }
});
