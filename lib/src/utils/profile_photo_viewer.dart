import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serafim/src/presentation/view/moment_viewer_page.dart';
import 'package:serafim/src/providers/moment_providers.dart';
import 'package:serafim/src/utils/moment_ring.dart';
import 'package:serafim/src/utils/chat/avatar_thumb.dart';
import 'package:serafim/src/utils/themes/app_colors.dart';
import 'package:serafim/src/utils/themes/app_text_styles.dart';

/// Opens [image] full screen with a hero flight from the avatar tagged
/// [heroTag]. Pinch to zoom; tap, or swipe down when not zoomed, to close.
/// With no photo it shows a large placeholder with [name]'s initials.
void openProfilePhoto(
  BuildContext context, {
  required ImageProvider? image,
  required String heroTag,
  required String name,
  bool isGroup = false,
}) {
  Navigator.of(context).push(
    PageRouteBuilder<void>(
      opaque: false,
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 260),
      reverseTransitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (_, __, ___) => ProfilePhotoViewer(
        image: image,
        heroTag: heroTag,
        name: name,
        isGroup: isGroup,
      ),
      transitionsBuilder: (_, animation, __, child) =>
          FadeTransition(opacity: animation, child: child),
    ),
  );
}

/// Initials for a placeholder: up to two letters from [name].
String initialsOf(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
  final letters = parts.take(2).map((p) => p.characters.first.toUpperCase());
  return letters.isEmpty ? '?' : letters.join();
}

class ProfilePhotoViewer extends StatefulWidget {
  const ProfilePhotoViewer({
    super.key,
    required this.image,
    required this.heroTag,
    required this.name,
    this.isGroup = false,
  });

  final ImageProvider? image;
  final String heroTag;
  final String name;
  final bool isGroup;

  @override
  State<ProfilePhotoViewer> createState() => _ProfilePhotoViewerState();
}

class _ProfilePhotoViewerState extends State<ProfilePhotoViewer>
    with SingleTickerProviderStateMixin {
  final _transform = TransformationController();
  late final AnimationController _settle = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 180),
  );

  double _dragY = 0;
  bool _zoomed = false;

  /// How far a swipe must travel (or how fast) to close the viewer.
  static const _dismissDistance = 120.0;
  static const _dismissVelocity = 700.0;

  @override
  void initState() {
    super.initState();
    _transform.addListener(() {
      final zoomed = _transform.value.getMaxScaleOnAxis() > 1.01;
      if (zoomed != _zoomed) setState(() => _zoomed = zoomed);
    });
  }

  @override
  void dispose() {
    _transform.dispose();
    _settle.dispose();
    super.dispose();
  }

  void _close() => Navigator.of(context).maybePop();

  void _onDragEnd(DragEndDetails d) {
    final v = d.primaryVelocity ?? 0;
    if (_dragY.abs() > _dismissDistance || v.abs() > _dismissVelocity) {
      _close();
      return;
    }
    // Spring back to the centre.
    final from = _dragY;
    final anim = Tween<double>(
      begin: from,
      end: 0,
    ).animate(CurvedAnimation(parent: _settle, curve: Curves.easeOut));
    void tick() => setState(() => _dragY = anim.value);
    anim.addListener(tick);
    _settle.forward(from: 0).whenComplete(() => anim.removeListener(tick));
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final side = size.shortestSide;
    final fade = (1 - (_dragY.abs() / (size.height * 0.6))).clamp(0.3, 1.0);
    final image = widget.image;

    final Widget photo = image != null
        ? Image(
            image: image,
            fit: BoxFit.contain,
            width: size.width,
            errorBuilder: (_, __, ___) => _Placeholder(
              name: widget.name,
              size: side * 0.7,
              isGroup: widget.isGroup,
            ),
          )
        : _Placeholder(
            name: widget.name,
            size: side * 0.7,
            isGroup: widget.isGroup,
          );

    return Scaffold(
      backgroundColor: Colors.black.withValues(alpha: 0.92 * fade),
      body: Stack(
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _close,
            // Swipe down (or up) to close, but not while zoomed in: then a
            // drag pans the photo instead.
            onVerticalDragUpdate: _zoomed
                ? null
                : (d) => setState(() => _dragY += d.delta.dy),
            onVerticalDragEnd: _zoomed ? null : _onDragEnd,
            child: Center(
              child: Transform.translate(
                offset: Offset(0, _dragY),
                child: InteractiveViewer(
                  transformationController: _transform,
                  minScale: 1,
                  maxScale: 4,
                  panEnabled: _zoomed,
                  child: Hero(tag: widget.heroTag, child: photo),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Opacity(
              opacity: fade,
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Close',
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: _close,
                  ),
                  Expanded(
                    child: Text(
                      widget.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.body.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({
    required this.name,
    required this.size,
    required this.isGroup,
  });

  final String name;
  final double size;
  final bool isGroup;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.line, width: 3),
        gradient: SweepGradient(
          colors: isGroup
              ? [AppColors.teal, AppColors.paper, AppColors.primaryDeep]
              : [AppColors.rust, AppColors.paper, AppColors.primary],
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            initialsOf(name),
            style: AppTextStyles.displayHeading.copyWith(
              fontSize: size * 0.3,
              color: Colors.white,
              shadows: const [Shadow(blurRadius: 6, color: Colors.black54)],
            ),
          ),
          Text(
            'No photo yet',
            style: AppTextStyles.fieldLabel.copyWith(color: Colors.white),
          ),
        ],
      ),
    );
  }
}

/// An avatar that opens the photo full screen when tapped. [heroTag] must be
/// unique on the screen (include where it is shown, e.g. `chats:<id>`).
///
/// Given a [userId], it also shows a coloured ring when that person has a
/// moment showing that you may see; tapping then plays their moments, and
/// pressing and holding opens the photo.
class TappableAvatar extends ConsumerStatefulWidget {
  const TappableAvatar({
    super.key,
    required this.image,
    required this.heroTag,
    required this.name,
    this.size = 38,
    this.isGroup = false,
    this.halo = false,
    this.userId,
  });

  /// Their halo is lit.
  final bool halo;

  final ImageProvider? image;
  final String heroTag;
  final String name;
  final double size;
  final bool isGroup;

  /// Whose avatar this is, to show their moments' ring. Null: no ring.
  final String? userId;

  @override
  ConsumerState<TappableAvatar> createState() => _TappableAvatarState();
}

class _TappableAvatarState extends ConsumerState<TappableAvatar> {
  @override
  void initState() {
    super.initState();
    _ask();
  }

  @override
  void didUpdateWidget(TappableAvatar old) {
    super.didUpdateWidget(old);
    if (old.userId != widget.userId) _ask();
  }

  void _ask() {
    final id = widget.userId;
    if (id == null) return;
    // After this frame: asking changes state, and building must not.
    Future.microtask(() {
      if (mounted) ref.read(momentRingsProvider.notifier).request(id);
    });
  }

  void _openPhoto() => openProfilePhoto(
    context,
    image: widget.image,
    heroTag: widget.heroTag,
    name: widget.name,
    isGroup: widget.isGroup,
  );

  @override
  Widget build(BuildContext context) {
    final id = widget.userId;
    final ring = id == null
        ? null
        : ref.watch(momentRingsProvider.select((rings) => rings[id]));
    final hasRing = ring != null;
    return Semantics(
      button: true,
      label: hasRing
          ? "View ${widget.name}'s moments"
          : "View ${widget.name}'s photo",
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: hasRing
            ? () => openMoments(
                context,
                userId: id!,
                name: widget.name,
                avatar: widget.image,
              )
            : _openPhoto,
        onLongPress: hasRing ? _openPhoto : null,
        child: Hero(
          tag: widget.heroTag,
          child: AvatarThumb(
            size: widget.size,
            imageProvider: widget.image,
            isGroup: widget.isGroup,
            halo: widget.halo,
            ring: MomentRingState.of(ring),
          ),
        ),
      ),
    );
  }
}
