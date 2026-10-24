import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serafim/src/data/models/public_user.dart';
import 'package:serafim/src/providers/social_providers.dart';
import 'package:serafim/src/providers/wings_providers.dart';
import 'package:serafim/src/utils/app_top_bar.dart';
import 'package:serafim/src/utils/chat/avatar_thumb.dart';
import 'package:serafim/src/utils/halo_style.dart';
import 'package:serafim/src/utils/settled_sheet.dart';
import 'package:serafim/src/utils/themes/app_colors.dart';
import 'package:serafim/src/utils/themes/app_text_styles.dart';
import 'package:serafim/src/utils/user_card.dart';
import 'package:serafim/src/utils/wing_mark.dart';

/// Your Wings: the six closest friends. Private — they are not told.
class WingsPage extends ConsumerWidget {
  const WingsPage({super.key});

  Future<void> _pick(BuildContext context, WidgetRef ref) async {
    final friend = await showSettledSheet<PublicUser>(
      context: context,
      backgroundColor: AppColors.paperAlt,
      shape: const RoundedRectangleBorder(),
      isScrollControlled: true,
      builder: (_) => const _FriendPicker(),
    );
    if (friend == null || !context.mounted) return;
    final error = await ref.read(wingsProvider.notifier).add(friend);
    if (error != null && context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error)));
    }
  }

  Future<void> _remove(
    BuildContext context,
    WidgetRef ref,
    PublicUser wing,
  ) async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.paperAlt,
        title: Text('Take ${wing.displayName} off your Wings?'),
        content: const Text('They are not told. They stay your friend.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (sure != true || !context.mounted) return;
    final error = await ref.read(wingsProvider.notifier).remove(wing.id);
    if (error != null && context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wings = ref.watch(wingsProvider);
    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppTopBar(
        title: 'YOUR WINGS',
        onBack: () => Navigator.of(context).pop(),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Row(
              children: [
                const WingMark(size: 22),
                const SizedBox(width: 10),
                Text(
                  '${wings.length} of $maxWings',
                  style: AppTextStyles.displayHeading.copyWith(fontSize: 20),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'Your six closest friends. Only you can see this list; they are '
              'never told. You can show your Halo to Wings only, and a message '
              'from a Wing always gets through.',
              style: AppTextStyles.body,
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final wing in wings)
                  _Slot(
                    key: ValueKey('wing-${wing.id}'),
                    onTap: () => _remove(context, ref, wing),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        AvatarThumb(
                          size: 52,
                          imageProvider: avatarImage(wing.profilePic),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          wing.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.smallDim.copyWith(
                            color: AppColors.text,
                          ),
                        ),
                      ],
                    ),
                  ),
                for (var i = wings.length; i < maxWings; i++)
                  _Slot(
                    key: ValueKey('wing-empty-$i'),
                    dashed: true,
                    onTap: () => _pick(context, ref),
                    child: Icon(Icons.add, color: haloColor, size: 28),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Slot extends StatelessWidget {
  const _Slot({
    super.key,
    required this.child,
    required this.onTap,
    this.dashed = false,
  });

  final Widget child;
  final VoidCallback onTap;
  final bool dashed;

  @override
  Widget build(BuildContext context) {
    final width = (MediaQuery.sizeOf(context).width - 40 - 24) / 3;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: width,
        height: width * 1.05,
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: AppColors.paperAlt,
          border: Border.all(
            color: dashed ? haloColor.withValues(alpha: 0.6) : haloColor,
            width: 1.5,
          ),
        ),
        child: Center(child: child),
      ),
    );
  }
}

/// Pick one of your friends who is not yet a Wing.
class _FriendPicker extends ConsumerStatefulWidget {
  const _FriendPicker();

  @override
  ConsumerState<_FriendPicker> createState() => _FriendPickerState();
}

class _FriendPickerState extends ConsumerState<_FriendPicker> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final friends = ref.watch(friendsViewProvider).friends;
    final wingIds = ref.watch(wingIdsProvider);
    final q = _query.trim().toLowerCase();
    final candidates = [
      for (final f in friends)
        if (!wingIds.contains(f.id) &&
            (q.isEmpty ||
                f.displayName.toLowerCase().contains(q) ||
                f.username.toLowerCase().contains(q)))
          f,
    ];
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.7,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: TextField(
                  key: const ValueKey('wing-search'),
                  onChanged: (v) => setState(() => _query = v),
                  decoration: const InputDecoration(
                    hintText: 'Search your friends',
                    prefixIcon: Icon(Icons.search),
                  ),
                ),
              ),
              Flexible(
                child: candidates.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          friends.isEmpty
                              ? 'Add some friends first.'
                              : 'No one left to choose.',
                          style: AppTextStyles.body,
                        ),
                      )
                    : ListView(
                        shrinkWrap: true,
                        children: [
                          for (final f in candidates)
                            ListTile(
                              key: ValueKey('pick-${f.id}'),
                              leading: AvatarThumb(
                                size: 38,
                                imageProvider: avatarImage(f.profilePic),
                              ),
                              title: Text(f.displayName),
                              subtitle: Text('@${f.username}'),
                              onTap: () => Navigator.pop(context, f),
                            ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
