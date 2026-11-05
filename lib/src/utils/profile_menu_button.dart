import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serafim/src/presentation/view/profile_page.dart';
import 'package:serafim/src/presentation/view/settings_page.dart';
import 'package:serafim/src/data/models/profile.dart';
import 'package:serafim/src/presentation/view/widgets/echo_send_card.dart';
import 'package:serafim/src/providers/echo_providers.dart';
import 'package:serafim/src/providers/halo_providers.dart';
import 'package:serafim/src/utils/echo_icon.dart';
import 'package:serafim/src/providers/profile_providers.dart';
import 'package:serafim/src/utils/halo_sheet.dart';
import 'package:serafim/src/utils/halo_style.dart';
import 'package:serafim/src/utils/chat/avatar_thumb.dart';
import 'package:serafim/src/utils/themes/app_colors.dart';
import 'package:serafim/src/utils/themes/app_text_styles.dart';

/// Your photo in the top bar of every main tab. It opens a short menu:
/// your profile, your Halo, an Echo, and settings.
///
/// On your own profile page [showProfile] is false: you are already there,
/// so the menu offers only Halo and Settings.
class ProfileMenuButton extends ConsumerWidget {
  const ProfileMenuButton({super.key, this.showProfile = true});

  final bool showProfile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pic = ref.watch(profileViewModelProvider).value?.profilePic;
    final haloLit = ref.watch(myHaloLitProvider);
    final echoesOn =
        ref.watch(profileViewModelProvider).value?.echoVisibility !=
        EchoVisibility.off;
    final myEcho = ref.watch(myEchoProvider).value;
    final live = myEcho?.echo;
    final echoLive =
        live != null && live.minutesLeft(DateTime.now().toUtc()) > 0;
    final avatar = pic != null && pic.isNotEmpty
        ? CachedNetworkImageProvider(pic)
        : null;
    return PopupMenuButton<String>(
      tooltip: 'Profile menu',
      padding: EdgeInsets.zero,
      // Drops below the photo, raised and outlined so it stands out from
      // the page behind it.
      position: PopupMenuPosition.under,
      offset: const Offset(0, 6),
      elevation: 10,
      color: AppColors.paperRaised,
      shadowColor: Colors.black,
      constraints: const BoxConstraints(minWidth: 190),
      shape: Border.all(color: AppColors.primary, width: 1.5),
      onSelected: (value) {
        if (value == 'halo') {
          showHaloSheet(context, ref);
          return;
        }
        if (value == 'echo') {
          // A live one shows how it is doing (and End); otherwise write one.
          echoLive
              ? showMyEchoSheet(context)
              : showEchoComposer(context, myEcho);
          return;
        }
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) =>
                value == 'profile' ? const ProfilePage() : const SettingsPage(),
          ),
        );
      },
      itemBuilder: (_) => [
        if (showProfile)
          _item('profile', Icons.person_outline_rounded, 'Profile'),
        _item(
          'halo',
          haloLit ? Icons.brightness_7_rounded : Icons.brightness_5_outlined,
          'Halo',
          color: haloLit ? haloColor : null,
          trailing: haloLit ? 'ON' : null,
        ),
        if (echoesOn)
          _item(
            'echo',
            null,
            'Echo',
            leading: EchoIcon(
              size: 20,
              color: echoLive ? haloColor : AppColors.primaryPale,
            ),
            color: echoLive ? haloColor : null,
            trailing: echoLive ? 'LIVE' : null,
          ),
        _item('settings', Icons.settings_outlined, 'Settings'),
      ],
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AvatarThumb(size: 28, imageProvider: avatar, halo: haloLit),
            // Says "this opens a menu" rather than leaving it to be found.
            Icon(
              Icons.arrow_drop_down_rounded,
              size: 18,
              color: AppColors.textDim,
            ),
          ],
        ),
      ),
    );
  }

  PopupMenuItem<String> _item(
    String value,
    IconData? icon,
    String label, {
    Color? color,
    String? trailing,
    Widget? leading,
  }) {
    return PopupMenuItem<String>(
      value: value,
      height: 46,
      child: Row(
        children: [
          leading ??
              Icon(icon, size: 20, color: color ?? AppColors.primaryPale),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: AppTextStyles.body.copyWith(
                color: AppColors.text,
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
          ),
          if (trailing != null)
            Text(
              trailing,
              style: AppTextStyles.smallDim.copyWith(
                color: color,
                fontWeight: FontWeight.w700,
              ),
            ),
        ],
      ),
    );
  }
}
