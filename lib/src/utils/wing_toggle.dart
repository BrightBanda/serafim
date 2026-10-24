import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serafim/src/data/models/public_user.dart';
import 'package:serafim/src/providers/wings_providers.dart';
import 'package:serafim/src/utils/halo_style.dart';
import 'package:serafim/src/utils/wing_mark.dart';

/// "Add to Wings" / "Remove from Wings" on a friend's profile. Only friends
/// can be Wings, so for anyone else it shows nothing.
class WingToggle extends ConsumerWidget {
  const WingToggle({super.key, required this.user});

  final PublicUser user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!user.isFriend) return const SizedBox.shrink();
    final isWing = ref.watch(isWingProvider(user.id));
    final full = ref.watch(wingsProvider).length >= maxWings;
    return OutlinedButton.icon(
      key: const ValueKey('wing-toggle'),
      onPressed: !isWing && full
          ? null
          : () async {
              final notifier = ref.read(wingsProvider.notifier);
              final error = isWing
                  ? await notifier.remove(user.id)
                  : await notifier.add(user);
              if (error != null && context.mounted) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text(error)));
              }
            },
      icon: const WingMark(size: 16),
      label: Text(
        isWing
            ? 'Remove from Wings'
            : (full ? 'Your Wings are full' : 'Add to Wings'),
      ),
      style: OutlinedButton.styleFrom(
        side: BorderSide(color: haloColor, width: 1.5),
        shape: const RoundedRectangleBorder(),
      ),
    );
  }
}
