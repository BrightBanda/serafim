import 'dart:async';

import 'package:flutter/material.dart';
import 'package:serafim/src/utils/chat/avatar_thumb.dart';
import 'package:serafim/src/utils/themes/app_colors.dart';
import 'package:serafim/src/utils/themes/app_text_styles.dart';

/// Shows banners at the top of the screen, in the *root* navigator's overlay,
/// so they sit above every page (and are not tied to any one Scaffold).
/// One banner at a time: a new message replaces the current one.
class InAppBannerService {
  InAppBannerService(this._navigatorKey);

  final GlobalKey<NavigatorState> _navigatorKey;
  OverlayEntry? _entry;
  Timer? _timer;

  static const _visibleFor = Duration(seconds: 4);

  void show({
    required String title,
    required String body,
    ImageProvider? avatar,
    Widget? leading,
    String label = 'NEW MESSAGE',
    IconData icon = Icons.chat_bubble_rounded,
    Color? accent,
    VoidCallback? onTap,
  }) {
    final overlay = _navigatorKey.currentState?.overlay;
    if (overlay == null) return;

    dismiss(animated: false);

    final controller = _BannerController();
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _BannerView(
        controller: controller,
        title: title,
        body: body,
        avatar: avatar,
        leading: leading,
        label: label,
        icon: icon,
        accent: accent,
        onTap: onTap,
      ),
    );
    _entry = entry;
    controller.onRemoved = () {
      if (_entry == entry) _entry = null;
      // Closed by a tap or flick: its auto-dismiss timer is no longer needed.
      if (identical(_controller, controller)) {
        _timer?.cancel();
        _controller = null;
      }
      entry.remove();
    };
    overlay.insert(entry);

    _timer = Timer(_visibleFor, () => controller.dismiss?.call());
    _controller = controller;
  }

  _BannerController? _controller;

  void dismiss({bool animated = true}) {
    _timer?.cancel();
    final controller = _controller;
    _controller = null;
    if (controller == null) return;
    if (animated && controller.dismiss != null) {
      controller.dismiss!();
    } else {
      controller.onRemoved?.call();
    }
  }
}

class _BannerController {
  VoidCallback? dismiss;
  VoidCallback? onRemoved;
}

class _BannerView extends StatefulWidget {
  const _BannerView({
    required this.controller,
    required this.title,
    required this.body,
    required this.label,
    required this.icon,
    this.avatar,
    this.leading,
    this.accent,
    this.onTap,
  });

  final _BannerController controller;
  final String title;
  final String body;
  final ImageProvider? avatar;

  /// Replaces the avatar (e.g. the SERAFIM logo for announcements).
  final Widget? leading;

  /// What kind of alert this is, e.g. "NEW MESSAGE".
  final String label;
  final IconData icon;

  /// Colour of the stripe and label chip; the brand blue when null.
  final Color? accent;
  final VoidCallback? onTap;

  @override
  State<_BannerView> createState() => _BannerViewState();
}

class _BannerViewState extends State<_BannerView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  );
  late final Animation<Offset> _slide = Tween<Offset>(
    begin: const Offset(0, -1.2),
    end: Offset.zero,
  ).animate(CurvedAnimation(parent: _anim, curve: Curves.easeOutCubic));

  bool _closing = false;

  @override
  void initState() {
    super.initState();
    widget.controller.dismiss = _close;
    _anim.forward();
  }

  @override
  void dispose() {
    widget.controller.dismiss = null;
    _anim.dispose();
    super.dispose();
  }

  Future<void> _close() async {
    if (_closing) return;
    _closing = true;
    if (mounted) await _anim.reverse();
    widget.controller.onRemoved?.call();
  }

  void _tap() {
    final onTap = widget.onTap;
    _close();
    onTap?.call();
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;

    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SlideTransition(
        position: _slide,
        child: Padding(
          padding: EdgeInsets.fromLTRB(12, top + 8, 12, 0),
          child: Material(
            type: MaterialType.transparency,
            child: GestureDetector(
              onTap: _tap,
              // Flick it up to dismiss.
              onVerticalDragEnd: (d) {
                if ((d.primaryVelocity ?? 0) < -150) _close();
              },
              child: _card(),
            ),
          ),
        ),
      ),
    );
  }

  /// A raised, lighter card than the page beneath it, with an accent stripe
  /// and a filled label chip, so it stands out in both themes.
  Widget _card() {
    final accent = widget.accent ?? AppColors.primary;
    final surface = Color.lerp(
      AppColors.isLight ? Colors.white : AppColors.paperRaised,
      accent,
      AppColors.isLight ? 0.07 : 0.16,
    )!;
    final surfaceEnd = AppColors.isLight ? Colors.white : AppColors.paperRaised;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [surface, surfaceEnd],
        ),
        border: Border.all(color: AppColors.line, width: 2),
        boxShadow: [
          BoxShadow(
            color: AppColors.line,
            offset: const Offset(3, 3),
            blurRadius: 0,
          ),
          BoxShadow(
            color: accent.withValues(alpha: 0.28),
            blurRadius: 18,
            spreadRadius: -2,
          ),
        ],
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 5, color: accent),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 10, 12, 10),
                child: Row(
                  children: [
                    widget.leading ??
                        AvatarThumb(size: 42, imageProvider: widget.avatar),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 5,
                              vertical: 1.5,
                            ),
                            color: accent,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(widget.icon, size: 9, color: Colors.white),
                                const SizedBox(width: 4),
                                Text(
                                  widget.label,
                                  style: AppTextStyles.fieldLabel.copyWith(
                                    fontSize: 8.5,
                                    color: Colors.white,
                                    letterSpacing: 0.8,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            widget.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.body.copyWith(
                              color: AppColors.text,
                              fontSize: 13.5,
                              fontWeight: FontWeight.w800,
                              height: 1.25,
                            ),
                          ),
                          if (widget.body.isNotEmpty)
                            Text(
                              widget.body,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyles.body.copyWith(
                                fontSize: 11.5,
                                height: 1.35,
                                color: AppColors.text.withValues(alpha: 0.82),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 18,
                      color: AppColors.textDim,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
