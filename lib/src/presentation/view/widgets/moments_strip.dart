import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serafim/src/data/models/moment.dart';
import 'package:serafim/src/data/models/public_user.dart';
import 'package:serafim/src/presentation/view/moment_composer_page.dart';
import 'package:serafim/src/presentation/view/moment_viewer_page.dart';
import 'package:serafim/src/providers/auth_providers.dart';
import 'package:serafim/src/providers/moment_providers.dart';
import 'package:serafim/src/providers/profile_providers.dart';
import 'package:serafim/src/providers/social_providers.dart';
import 'package:serafim/src/utils/chat/avatar_thumb.dart';
import 'package:serafim/src/utils/moment_ring.dart';
import 'package:serafim/src/utils/themes/app_colors.dart';
import 'package:serafim/src/utils/themes/app_text_styles.dart';

/// Moments, along the top of the feed: yours first (with a + to add one), then
/// friends who have one showing, the ones you haven't seen first. Tapping a
/// person plays their moments.
class MomentsStrip extends ConsumerWidget {
  const MomentsStrip({super.key});

  static const height = 96.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(currentAccountIdProvider);
    if (me == null) return const SizedBox.shrink();
    // Rings follow what was looked at since the list was fetched.
    final rings = ref.watch(momentRingsProvider);
    final feed = ref.watch(friendMomentsProvider).value ?? const [];
    final friends = {
      for (final f in ref.watch(friendsViewProvider).friends) f.id: f,
    };
    final others = [
      for (final r in feed)
        if (friends[r.userId] != null && r.userId != me)
          (friend: friends[r.userId]!, ring: rings[r.userId] ?? r),
    ];
    // Unseen first, in the server's order within each group.
    final ordered = [
      ...others.where((o) => !o.ring.allSeen),
      ...others.where((o) => o.ring.allSeen),
    ];

    return SizedBox(
      height: height,
      child: ListView(
        key: const ValueKey('moments-strip'),
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
        children: [
          _Mine(me: me),
          for (final o in ordered) _Friend(friend: o.friend, ring: o.ring),
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.tileKey,
    required this.label,
    required this.onTap,
    required this.avatar,
  });

  final Key tileKey;
  final String label;
  final VoidCallback onTap;
  final Widget avatar;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: GestureDetector(
        key: tileKey,
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: 66,
          child: Column(
            children: [
              avatar,
              const SizedBox(height: 5),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: AppTextStyles.smallDim.copyWith(
                  color: AppColors.text,
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Your own tile: your moments if you have any showing, and a + to add more.
class _Mine extends ConsumerWidget {
  const _Mine({required this.me});

  final String me;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileViewModelProvider).value;
    final pic = profile?.profilePic;
    final image = pic != null && pic.isNotEmpty
        ? CachedNetworkImageProvider(pic)
        : null;
    final mine = ref.watch(myMomentsProvider).value ?? const [];
    final has = mine.isNotEmpty;
    // Yours always shows bright while it is up: you made it, so "unseen"
    // would mean nothing; the colour says "this is live".
    final ring = has ? MomentRingState.unseen : MomentRingState.none;

    Future<void> add() async {
      final posted = await openMomentComposer(context);
      ref.invalidate(myMomentsProvider);
      if (posted && context.mounted) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(
            const SnackBar(content: Text('Your moment is up for 24 hours.')),
          );
      }
    }

    return _Tile(
      tileKey: const ValueKey('moments-mine'),
      // Short enough to read whole in the tile.
      label: has ? 'My moment' : 'Add moment',
      onTap: has
          ? () => openMoments(
              context,
              userId: me,
              name: profile?.displayName ?? 'You',
              avatar: image,
            ).then((_) => ref.invalidate(myMomentsProvider))
          : add,
      avatar: SizedBox(
        width: 58,
        height: 58,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            AvatarThumb(size: 58, imageProvider: image, ring: ring),
            Positioned(
              right: -2,
              bottom: -2,
              child: GestureDetector(
                key: const ValueKey('moments-add'),
                onTap: add,
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.paper, width: 2),
                  ),
                  child: const Icon(Icons.add, size: 14, color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Friend extends ConsumerWidget {
  const _Friend({required this.friend, required this.ring});

  final PublicUser friend;
  final MomentRing ring;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pic = friend.profilePic;
    final image = pic != null && pic.isNotEmpty
        ? CachedNetworkImageProvider(pic)
        : null;
    return _Tile(
      tileKey: ValueKey('moments-friend-${friend.id}'),
      label: friend.displayName,
      onTap: () => openMoments(
        context,
        userId: friend.id,
        name: friend.displayName,
        avatar: image,
      ),
      avatar: AvatarThumb(
        size: 58,
        imageProvider: image,
        ring: MomentRingState.of(ring),
      ),
    );
  }
}
