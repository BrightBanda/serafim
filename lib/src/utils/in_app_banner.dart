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
    this.avatar,
    this.onTap,
  });

  final _BannerController controller;
  final String title;
  final String body;
  final ImageProvider? avatar;
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
              child: Container(
                padding: const EdgeInsets.symmetric(
                  vertical: 10,
                  horizontal: 12,
                ),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [AppColors.paperRaised, AppColors.paperAlt],
                  ),
                  border: Border.all(color: AppColors.line, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.line,
                      offset: const Offset(3, 3),
                      blurRadius: 0,
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    AvatarThumb(size: 40, imageProvider: widget.avatar),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'NEW MESSAGE',
                            style: AppTextStyles.fieldLabel.copyWith(
                              fontSize: 8.5,
                              color: AppColors.primaryPale,
                            ),
                          ),
                          const SizedBox(height: 1),
                          Text(
                            widget.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.body.copyWith(
                              color: AppColors.text,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            widget.body,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.body.copyWith(fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
